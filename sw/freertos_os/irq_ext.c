// /* irq_ext.c — PLIC external-interrupt integration with FreeRTOS.
//  *
//  * Five PLIC sources, all routed through the weak-handler override the port calls
//  * for every non-timer interrupt. Each peripheral uses a DIFFERENT clear
//  * mechanism — the point of exercising all five:
//  *
//  *   UART RX-available -> uart_irq   -> PLIC id 1 (level) -> push byte to queue  | clear: read RBR
//  *   APB timer cmp/ovf -> timer_irq  -> PLIC id 2 (level) -> notify xTimerTaskH  | clear: AUTO (self-reset)
//  *   I2C transfer-done -> i2c_irq    -> PLIC id 3 (level) -> notify xI2cTaskH    | clear: write IACK bit
//  *   SPI end-of-xfer   -> spi_irq    -> PLIC id 4 (level) -> notify xSpiTaskH    | clear: read INTSTA
//  *   GPIO rising edge  -> gpio_irq   -> PLIC id 5 (edge)  -> notify xGpioTaskH   | clear: write-1 status
//  *
//  * The APB timer (distinct from the CLINT that drives the FreeRTOS scheduler
//  * tick) is a general-purpose peripheral timer with its own PLIC source. Two
//  * timers are instantiated in the SoC (soc_top: TIMER_CNT=2); this integration
//  * uses timer 0. Its interrupt behavior is unique among the peripherals: on
//  * compare-match, the timer register self-resets to 0, which causes irq_o to
//  * de-assert the same cycle it fires — an "auto-clear on trigger" pattern.
//  * The ISR therefore doesn't touch the timer registers; it just notifies.
//  *
//  * Hardware facts (soc_top.sv / vendor blocks / rv_plic):
//  *   GPIO 0x1000_4000: EN@+0x080, INTRPT_RISE_EN@+0x380, STATUS@+0x580 (W1C),
//  *                     RISE_STATUS@+0x600 (W1C)
//  *   UART 0x1000_0000: 16550. IER@1, LSR@5(DR=bit0), RBR@0 (read clears RX int)
//  *   TMR  0x1000_1000: apb_timer, timer 0: TIMER@0, CTRL@4 (bit0 EN, bits[5:3]
//  *                     prescaler), CMP@8. irq_o[1]=cmp match; register self-
//  *                     resets on trigger, so no explicit clear is required.
//  *   I2C  0x1000_2000: OpenCores. CMD@0x14 (bit0 IACK clears the interrupt)
//  *   SPI  0x1000_3000: PULP apb_spi. INTSTA@0x28 (read clears the interrupt)
//  *   PLIC 0x1040_0000: uart=1(level), tmr=2(level), i2c=3(level), spi=4(level),
//  *                     gpio=5(edge)
//  */
// #include "FreeRTOS.h"
// #include "task.h"
// #include "queue.h"
// #include <stdint.h>

// #define REG32(a)            (*(volatile uint32_t *)(a))
// #define REG8(a)             (*(volatile uint8_t  *)(a))

// /* ---- GPIO ---- */
// #define GPIO_BASE           0x10004000u
// #define GPIO_EN             REG32(GPIO_BASE + 0x080)
// #define GPIO_INTRPT_RISE_EN REG32(GPIO_BASE + 0x380)
// #define GPIO_INTRPT_STATUS  REG32(GPIO_BASE + 0x580)
// #define GPIO_INTRPT_RISE_ST REG32(GPIO_BASE + 0x600)

// /* ---- UART (16550) ---- */
// #define UART_BASE           0x10000000u
// #define UART_RBR            REG8(UART_BASE + 0)
// #define UART_IER            REG8(UART_BASE + 1)
// #define UART_LSR            REG8(UART_BASE + 5)
// #define UART_LSR_DR         0x01u

// /* ---- APB timer (timer 0) ---- */
// #define TMR_BASE            0x10001000u
// #define TMR_TIMER           REG32(TMR_BASE + 0x0)   /* running counter          */
// #define TMR_CTRL            REG32(TMR_BASE + 0x4)   /* bit0 EN, bits[5:3] presc */
// #define TMR_CMP             REG32(TMR_BASE + 0x8)   /* compare value            */
// #define TMR_CTRL_EN         0x01u

// /* ---- I2C (OpenCores) ---- */
// #define I2C_BASE            0x10002000u
// #define I2C_CMD             REG32(I2C_BASE + 0x14)
// #define I2C_CMD_IACK        0x01u

// /* ---- SPI (PULP apb_spi_master) ---- */
// #define SPI_BASE            0x10003000u
// #define SPI_INTSTA          REG32(SPI_BASE + 0x28)   /* read clears the interrupt */

// /* ---- PLIC (context 0) ---- */
// #define PLIC_BASE           0x10400000u
// #define PLIC_SRC_UART       1u
// #define PLIC_SRC_TMR        2u
// #define PLIC_SRC_I2C        3u
// #define PLIC_SRC_SPI        4u
// #define PLIC_SRC_GPIO       5u
// #define PLIC_PRIORITY(id)   REG32(PLIC_BASE + 4u * (id))
// #define PLIC_ENABLE0        REG32(PLIC_BASE + 0x2000u)
// #define PLIC_THRESHOLD0     REG32(PLIC_BASE + 0x200000u)
// #define PLIC_CLAIM0         REG32(PLIC_BASE + 0x200004u)

// extern TaskHandle_t  xGpioTaskHandle;
// extern TaskHandle_t  xI2cTaskHandle;
// extern TaskHandle_t  xSpiTaskHandle;
// extern TaskHandle_t  xTmrTaskHandle;
// extern QueueHandle_t xUartRxQueue;

// volatile uint32_t ulExtIrqCount = 0;

// void ext_irq_init( void )
// {
//     GPIO_EN             |= 1u;
//     GPIO_INTRPT_RISE_EN |= 1u;

//     UART_IER |= 0x01u;

//     PLIC_PRIORITY( PLIC_SRC_UART ) = 1u;
//     PLIC_PRIORITY( PLIC_SRC_TMR  ) = 1u;
//     PLIC_PRIORITY( PLIC_SRC_I2C  ) = 1u;
//     PLIC_PRIORITY( PLIC_SRC_SPI  ) = 1u;
//     PLIC_PRIORITY( PLIC_SRC_GPIO ) = 1u;
//     PLIC_ENABLE0   |= ( 1u << PLIC_SRC_UART )
//                    |  ( 1u << PLIC_SRC_TMR  )
//                    |  ( 1u << PLIC_SRC_I2C  )
//                    |  ( 1u << PLIC_SRC_SPI  )
//                    |  ( 1u << PLIC_SRC_GPIO );
//     PLIC_THRESHOLD0 = 0u;

//     __asm__ volatile ( "csrs mie, %0" :: "r"( 1u << 11 ) );  /* mie.MEIE */
// }

// void freertos_risc_v_application_interrupt_handler( void )
// {
//     BaseType_t xWoken = pdFALSE;
//     uint32_t   ulId;

//     while ( ( ulId = PLIC_CLAIM0 ) != 0u )
//     {
//         if ( ulId == PLIC_SRC_GPIO )
//         {
//             GPIO_INTRPT_RISE_ST = 1u;                   /* W1C */
//             GPIO_INTRPT_STATUS  = 1u;                   /* W1C */
//             ulExtIrqCount++;
//             if ( xGpioTaskHandle != NULL )
//                 vTaskNotifyGiveFromISR( xGpioTaskHandle, &xWoken );
//         }
//         else if ( ulId == PLIC_SRC_UART )
//         {
//             while ( UART_LSR & UART_LSR_DR )
//             {
//                 uint8_t b = UART_RBR;                    /* read clears RX int */
//                 ulExtIrqCount++;
//                 if ( xUartRxQueue != NULL )
//                     xQueueSendFromISR( xUartRxQueue, &b, &xWoken );
//             }
//         }
//         else if ( ulId == PLIC_SRC_TMR )
//         {
//             /* apb_timer auto-clears on trigger: the timer register self-resets
//              * to 0, dropping irq_o the same cycle. No register write needed
//              * from the ISR — this is the "auto-clear on trigger" pattern. */
//             ulExtIrqCount++;
//             if ( xTmrTaskHandle != NULL )
//                 vTaskNotifyGiveFromISR( xTmrTaskHandle, &xWoken );
//         }
//         else if ( ulId == PLIC_SRC_I2C )
//         {
//             I2C_CMD = I2C_CMD_IACK;                      /* clear I2C interrupt */
//             ulExtIrqCount++;
//             if ( xI2cTaskHandle != NULL )
//                 vTaskNotifyGiveFromISR( xI2cTaskHandle, &xWoken );
//         }
//         else if ( ulId == PLIC_SRC_SPI )
//         {
//             (void) SPI_INTSTA;                           /* read clears SPI int */
//             ulExtIrqCount++;
//             if ( xSpiTaskHandle != NULL )
//                 vTaskNotifyGiveFromISR( xSpiTaskHandle, &xWoken );
//         }
//         PLIC_CLAIM0 = ulId;                             /* complete */
//     }

//     portYIELD_FROM_ISR( xWoken );
// }


/* irq_ext.c — PLIC external-interrupt integration with FreeRTOS.
 *
 * Five PLIC sources, all routed through the weak-handler override the port calls
 * for every non-timer interrupt. Each peripheral uses a DIFFERENT clear
 * mechanism — the point of exercising all five:
 *
 *   UART RX-available -> uart_irq   -> PLIC id 1 (level) -> push byte to queue  | clear: read RBR
 *   APB timer cmp/ovf -> timer_irq  -> PLIC id 2 (level) -> notify xTimerTaskH  | clear: AUTO (self-reset)
 *   I2C transfer-done -> i2c_irq    -> PLIC id 3 (level) -> notify xI2cTaskH    | clear: write IACK bit
 *   SPI end-of-xfer   -> spi_irq    -> PLIC id 4 (level) -> notify xSpiTaskH    | clear: read INTSTA
 *   GPIO rising edge  -> gpio_irq   -> PLIC id 5 (edge)  -> notify xGpioTaskH   | clear: write-1 status
 *
 * The APB timer (distinct from the CLINT that drives the FreeRTOS scheduler
 * tick) is a general-purpose peripheral timer with its own PLIC source. Two
 * timers are instantiated in the SoC (soc_top: TIMER_CNT=2); this integration
 * uses timer 0. Its interrupt behavior is unique among the peripherals: on
 * compare-match, the timer register self-resets to 0, which causes irq_o to
 * de-assert the same cycle it fires — an "auto-clear on trigger" pattern.
 * The ISR therefore doesn't touch the timer registers; it just notifies.
 *
 * Hardware facts (soc_top.sv / vendor blocks / rv_plic):
 *   GPIO 0x1000_4000: EN@+0x080, INTRPT_RISE_EN@+0x380, STATUS@+0x580 (W1C),
 *                     RISE_STATUS@+0x600 (W1C)
 *   UART 0x1000_0000: 16550. IER@1, LSR@5(DR=bit0), RBR@0 (read clears RX int)
 *   TMR  0x1000_1000: apb_timer, timer 0: TIMER@0, CTRL@4 (bit0 EN, bits[5:3]
 *                     prescaler), CMP@8. irq_o[1]=cmp match; register self-
 *                     resets on trigger, so no explicit clear is required.
 *   I2C  0x1000_2000: OpenCores. CMD@0x14 (bit0 IACK clears the interrupt)
 *   SPI  0x1000_3000: PULP apb_spi. INTSTA@0x28 (read clears the interrupt)
 *   PLIC 0x1040_0000: uart=1(level), tmr=2(level), i2c=3(level), spi=4(level),
 *                     gpio=5(edge)
 */
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include <stdint.h>

#define REG32(a)            (*(volatile uint32_t *)(a))
#define REG8(a)             (*(volatile uint8_t  *)(a))

/* ---- GPIO ---- */
#define GPIO_BASE           0x10004000u
#define GPIO_EN             REG32(GPIO_BASE + 0x080)
#define GPIO_INTRPT_RISE_EN REG32(GPIO_BASE + 0x380)
#define GPIO_INTRPT_STATUS  REG32(GPIO_BASE + 0x580)
#define GPIO_INTRPT_RISE_ST REG32(GPIO_BASE + 0x600)

/* ---- UART (16550) ---- */
#define UART_BASE           0x10000000u
#define UART_RBR            REG8(UART_BASE + 0)
#define UART_IER            REG8(UART_BASE + 1)
#define UART_LSR            REG8(UART_BASE + 5)
#define UART_LSR_DR         0x01u

/* ---- APB timer (timer 0) ---- */
#define TMR_BASE            0x10001000u
#define TMR_TIMER           REG32(TMR_BASE + 0x0)   /* running counter          */
#define TMR_CTRL            REG32(TMR_BASE + 0x4)   /* bit0 EN, bits[5:3] presc */
#define TMR_CMP             REG32(TMR_BASE + 0x8)   /* compare value            */
#define TMR_CTRL_EN         0x01u

/* ---- I2C (OpenCores) ---- */
#define I2C_BASE            0x10002000u
#define I2C_CMD             REG32(I2C_BASE + 0x14)
#define I2C_CMD_IACK        0x01u

/* ---- SPI (PULP apb_spi_master) ---- */
#define SPI_BASE            0x10003000u
#define SPI_INTSTA          REG32(SPI_BASE + 0x28)   /* read clears the interrupt */

/* ---- PLIC (context 0) ---- */
#define PLIC_BASE           0x10400000u
#define PLIC_SRC_UART       1u
#define PLIC_SRC_TMR        2u
#define PLIC_SRC_I2C        3u
#define PLIC_SRC_SPI        4u
#define PLIC_SRC_GPIO       5u
#define PLIC_PRIORITY(id)   REG32(PLIC_BASE + 4u * (id))
#define PLIC_ENABLE0        REG32(PLIC_BASE + 0x2000u)
#define PLIC_THRESHOLD0     REG32(PLIC_BASE + 0x200000u)
#define PLIC_CLAIM0         REG32(PLIC_BASE + 0x200004u)

extern TaskHandle_t  xGpioTaskHandle;
extern TaskHandle_t  xI2cTaskHandle;
extern TaskHandle_t  xSpiTaskHandle;
extern TaskHandle_t  xTmrTaskHandle;
extern QueueHandle_t xUartRxQueue;

volatile uint32_t ulExtIrqCount = 0;

void ext_irq_init( void )
{
    GPIO_EN             |= 1u;
    GPIO_INTRPT_RISE_EN |= 1u;

    UART_IER |= 0x01u;

    /* Distinct PLIC priorities (higher number = higher priority). This lets the
     * PLIC arbitrate correctly when multiple sources fire on the same cycle:
     * the highest-priority source is claimed first, its ISR runs, PLIC is
     * completed, then the next-highest source's pending bit becomes claimable.
     *
     * Ordering chosen so the priority test tb_prio_os can observe the claim
     * order: GPIO (edge, fast to service) preempts UART (level, slower drain).
     * Middle sources (TMR/I2C/SPI) get a middle priority so they don't starve
     * the low-priority UART during normal operation. */
    PLIC_PRIORITY( PLIC_SRC_GPIO ) = 5u;   /* highest */
    PLIC_PRIORITY( PLIC_SRC_TMR  ) = 3u;
    PLIC_PRIORITY( PLIC_SRC_I2C  ) = 3u;
    PLIC_PRIORITY( PLIC_SRC_SPI  ) = 3u;
    PLIC_PRIORITY( PLIC_SRC_UART ) = 1u;   /* lowest */
    PLIC_ENABLE0   |= ( 1u << PLIC_SRC_UART )
                   |  ( 1u << PLIC_SRC_TMR  )
                   |  ( 1u << PLIC_SRC_I2C  )
                   |  ( 1u << PLIC_SRC_SPI  )
                   |  ( 1u << PLIC_SRC_GPIO );
    PLIC_THRESHOLD0 = 0u;

    __asm__ volatile ( "csrs mie, %0" :: "r"( 1u << 11 ) );  /* mie.MEIE */
}

void freertos_risc_v_application_interrupt_handler( void )
{
    BaseType_t xWoken = pdFALSE;
    uint32_t   ulId;

    while ( ( ulId = PLIC_CLAIM0 ) != 0u )
    {
        if ( ulId == PLIC_SRC_GPIO )
        {
            GPIO_INTRPT_RISE_ST = 1u;                   /* W1C */
            GPIO_INTRPT_STATUS  = 1u;                   /* W1C */
            ulExtIrqCount++;
            if ( xGpioTaskHandle != NULL )
                vTaskNotifyGiveFromISR( xGpioTaskHandle, &xWoken );
        }
        else if ( ulId == PLIC_SRC_UART )
        {
            while ( UART_LSR & UART_LSR_DR )
            {
                uint8_t b = UART_RBR;                    /* read clears RX int */
                ulExtIrqCount++;
                if ( xUartRxQueue != NULL )
                    xQueueSendFromISR( xUartRxQueue, &b, &xWoken );
            }
        }
        else if ( ulId == PLIC_SRC_TMR )
        {
            /* apb_timer auto-clears on trigger: the timer register self-resets
             * to 0, dropping irq_o the same cycle. No register write needed
             * from the ISR — this is the "auto-clear on trigger" pattern. */
            ulExtIrqCount++;
            if ( xTmrTaskHandle != NULL )
                vTaskNotifyGiveFromISR( xTmrTaskHandle, &xWoken );
        }
        else if ( ulId == PLIC_SRC_I2C )
        {
            I2C_CMD = I2C_CMD_IACK;                      /* clear I2C interrupt */
            ulExtIrqCount++;
            if ( xI2cTaskHandle != NULL )
                vTaskNotifyGiveFromISR( xI2cTaskHandle, &xWoken );
        }
        else if ( ulId == PLIC_SRC_SPI )
        {
            (void) SPI_INTSTA;                           /* read clears SPI int */
            ulExtIrqCount++;
            if ( xSpiTaskHandle != NULL )
                vTaskNotifyGiveFromISR( xSpiTaskHandle, &xWoken );
        }
        PLIC_CLAIM0 = ulId;                             /* complete */
    }

    portYIELD_FROM_ISR( xWoken );
}