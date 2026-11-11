/* main.c — FreeRTOS demo exercising all OS-level trap classes AND three
 * peripheral interrupt sources (each with a different clear mechanism):
 *   - timer interrupts : tasks A, B (blinky, context-switch on tick)
 *   - GPIO interrupt    : task G, woken by a GPIO rising edge (W1C clear)
 *   - UART RX interrupt : task U, echoes each received byte (read-to-clear)
 *   - I2C done interrupt: task I, interrupt-driven read of a slave (IACK clear)
 *
 * UART safety: uart_puts() is mutex-protected (see uart.c). The UART ISR pushes
 * bytes to xUartRxQueue; task U echoes. The I2C ISR acks the interrupt (IACK)
 * and notifies task I, which drives the transaction step-by-step, blocking on a
 * notification between the address phase and the data phase.
 */
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "uart.h"
#include <stdint.h>

extern void freertos_risc_v_trap_handler( void );
extern void ext_irq_init( void );

#define REG32(a)     (*(volatile uint32_t *)(a))
#define REG8(a)      (*(volatile uint8_t  *)(a))
#define GPIO_TOGGLE  REG32(0x10004000u + 0x300u)

/* ---- I2C register map (OpenCores apb_i2c) ---- */
#define I2C_BASE     0x10002000u
#define I2C_PRER     REG32(I2C_BASE + 0x00)
#define I2C_CTRL     REG32(I2C_BASE + 0x04)
#define I2C_RX       REG32(I2C_BASE + 0x08)
#define I2C_STATUS   REG32(I2C_BASE + 0x0C)
#define I2C_TX       REG32(I2C_BASE + 0x10)
#define I2C_CMD      REG32(I2C_BASE + 0x14)
/* CTRL bits: 0x80 core enable, 0x40 interrupt enable (IEN)                    */
/* CMD  bits: 0x80 START, 0x40 STOP, 0x20 READ, 0x10 WRITE, 0x08 ACK(NACK=1),  */
/*            0x01 IACK                                                         */
#define I2C_SLAVE_RD 0x89u   /* (0x44 << 1) | 1  = slave 0x44, read            */

/* ---- SPI register map (PULP apb_spi_master) ---- */
#define SPI_BASE     0x10003000u
#define SPI_STATUS   REG32(SPI_BASE + 0x00)   /* w: bit0 rd, bits[11:8] cs; r: status */
#define SPI_CLKDIV   REG32(SPI_BASE + 0x04)
#define SPI_SPILEN   REG32(SPI_BASE + 0x10)   /* data length (bits) in [15:0]          */
#define SPI_RXFIFO   REG32(SPI_BASE + 0x20)
#define SPI_INTSTA   REG32(SPI_BASE + 0x28)   /* read clears the interrupt             */

/* ---- APB timer register map (timer 0) ---- */
#define TMR_BASE     0x10001000u
#define TMR_TIMER    REG32(TMR_BASE + 0x0)     /* running counter                       */
#define TMR_CTRL     REG32(TMR_BASE + 0x4)     /* bit0=enable, bits[5:3]=prescaler      */
#define TMR_CMP      REG32(TMR_BASE + 0x8)     /* compare value                         */

TaskHandle_t  xGpioTaskHandle = NULL;
TaskHandle_t  xI2cTaskHandle  = NULL;
TaskHandle_t  xSpiTaskHandle  = NULL;
TaskHandle_t  xTmrTaskHandle  = NULL;
QueueHandle_t xUartRxQueue    = NULL;

static void put_hex_byte( uint8_t b )
{
    const char *h = "0123456789ABCDEF";
    char out[5];
    out[0] = '0'; out[1] = 'x';
    out[2] = h[(b >> 4) & 0xF];
    out[3] = h[b & 0xF];
    out[4] = '\0';
    uart_puts( out );
}

static void vTaskA( void *pv ) { (void)pv;
    for(;;){ uart_puts("A\n"); GPIO_TOGGLE=(1u<<4); vTaskDelay(pdMS_TO_TICKS(2)); } }

static void vTaskB( void *pv ) { (void)pv;
    for(;;){ uart_puts("B\n"); GPIO_TOGGLE=(1u<<5); vTaskDelay(pdMS_TO_TICKS(3)); } }

static void vTaskG( void *pv ) { (void)pv;
    for(;;){ ulTaskNotifyTake(pdTRUE, portMAX_DELAY); uart_puts("G\n"); } }

static void vTaskU( void *pv )
{
    uint8_t b; char out[6]; (void)pv;
    for(;;){
        if ( xQueueReceive( xUartRxQueue, &b, portMAX_DELAY ) == pdTRUE ) {
            out[0]='['; out[1]='U'; out[2]=':'; out[3]=(char)b; out[4]=']'; out[5]='\0';
            uart_puts(out); uart_puts("\n");
        }
    }
}

/* Interrupt-driven I2C read of slave 0x44. Each command completion raises the
 * I2C interrupt; the ISR acks it (IACK) and notifies us. We block between the
 * address phase and the data phase rather than polling STATUS. */
static void vTaskI( void *pv )
{
    (void) pv;

    /* One-time I2C core setup: prescaler, core enable + interrupt enable. */
    I2C_PRER = 8u;
    I2C_CTRL = 0x80u | 0x40u;             /* core enable | IEN */

    vTaskDelay( pdMS_TO_TICKS( 5 ) );     /* let A/B/greeting settle first */

    for( ;; )
    {
        /* Phase 1: send slave address + read bit, with START. */
        I2C_TX  = I2C_SLAVE_RD;
        I2C_CMD = 0x90u;                  /* START | WRITE */
        ulTaskNotifyTake( pdTRUE, portMAX_DELAY );   /* wait for done irq */

        /* Phase 2: read one byte, then STOP with NACK. */
        I2C_CMD = 0x20u | 0x40u | 0x08u;  /* READ | STOP | NACK */
        ulTaskNotifyTake( pdTRUE, portMAX_DELAY );   /* wait for done irq */

        /* Read the received byte and report it. */
        uint8_t rx = (uint8_t) I2C_RX;
        uart_puts("[I:");
        put_hex_byte( rx );
        uart_puts("]\n");

        vTaskDelay( pdMS_TO_TICKS( 50 ) );  /* repeat periodically */
    }
}

/* Interrupt-driven SPI read of a slave that shifts out 0xC3 (mode-0, MSB-first).
 * The apb_spi EOT event (events_o[1]) raises the PLIC interrupt; the ISR reads
 * INTSTA to clear it and notifies us. */
static void vTaskS( void *pv )
{
    (void) pv;

    SPI_CLKDIV = 4u;                       /* SPI clock divider */

    vTaskDelay( pdMS_TO_TICKS( 8 ) );      /* let A/B/greeting settle */

    for( ;; )
    {
        /* SPILEN: data_len is in bits [23:16] (cmd_len[5:0], addr_len[13:8]).
         * 8 data bits => 8<<16. (Writing 8<<0 sets cmd_len=8, data_len=0 -> no
         * transfer, which is the classic "CS never asserts" mistake.) */
        SPI_SPILEN = ( 8u << 16 );
        /* STATUS: bit0 = spi_rd (start read); bits[11:8] = csreg. csn0 asserts
         * only when csreg[0]=1 (spi_csn0 = ~csreg[0] | cs), so select CS0 with
         * bit8 => 0x101, NOT 0x001. */
        SPI_STATUS = 0x101u;

        ulTaskNotifyTake( pdTRUE, portMAX_DELAY );   /* wait for EOT irq */

        uint8_t rx = (uint8_t) SPI_RXFIFO;
        uart_puts("[S:");
        {
            const char *h = "0123456789ABCDEF";
            char o[5]; o[0]='0'; o[1]='x'; o[2]=h[(rx>>4)&0xF]; o[3]=h[rx&0xF]; o[4]='\0';
            uart_puts(o);
        }
        uart_puts("]\n");

        vTaskDelay( pdMS_TO_TICKS( 50 ) );
    }
}

/* APB timer task: enables timer 0 with a compare match, blocks on the
 * interrupt-driven notification (see irq_ext.c PLIC_SRC_TMR branch). The timer
 * register self-resets on match, so it re-fires periodically without any ISR
 * write. Prints [T:n] each time it wakes. */
static void vTaskT( void *pv )
{
    (void) pv;

    vTaskDelay( pdMS_TO_TICKS( 10 ) );   /* let greeting + A/B settle first */

    TMR_CMP   = 20000u;                  /* compare match after 20 000 core cycles */
    TMR_TIMER = 0u;                      /* clear counter                          */
    TMR_CTRL  = 0x01u;                   /* enable, no prescaler                   */

    for( ;; )
    {
        ulTaskNotifyTake( pdTRUE, portMAX_DELAY );
        uart_puts("[T]\n");
    }
}

void vAssertCalled( const char *file, int line )
{ (void)file; (void)line; uart_puts("ASSERT\n"); taskDISABLE_INTERRUPTS(); for(;;){} }

int main( void )
{
    uart_init( 16 );
    uart_puts("FreeRTOS blinky start\n");

    __asm__ volatile ( "csrw mtvec, %0" :: "r"( freertos_risc_v_trap_handler ) );

    xUartRxQueue = xQueueCreate( 16, sizeof( uint8_t ) );

    ext_irq_init();

    xTaskCreate( vTaskA, "A", configMINIMAL_STACK_SIZE, NULL, 1, NULL );
    xTaskCreate( vTaskB, "B", configMINIMAL_STACK_SIZE, NULL, 1, NULL );
    /* Task G runs at FreeRTOS priority 3 — one above U/I/S/T (all prio 2). This
     * makes the task-execution order match the PLIC hardware priority
     * arbitration (GPIO PLIC prio 5 > UART PLIC prio 1), so [G] prints before
     * [U:X] when both interrupts fire simultaneously (see tb_prio_os). */
    xTaskCreate( vTaskG, "G", configMINIMAL_STACK_SIZE, NULL, 3, &xGpioTaskHandle );
    xTaskCreate( vTaskU, "U", configMINIMAL_STACK_SIZE, NULL, 2, NULL );
    xTaskCreate( vTaskI, "I", configMINIMAL_STACK_SIZE, NULL, 2, &xI2cTaskHandle );
    xTaskCreate( vTaskS, "S", configMINIMAL_STACK_SIZE, NULL, 2, &xSpiTaskHandle );
    xTaskCreate( vTaskT, "T", configMINIMAL_STACK_SIZE, NULL, 2, &xTmrTaskHandle );

    vTaskStartScheduler();

    uart_puts("SCHED FAIL\n");
    for( ;; ) { }
    return 0;
}