#include "uart.h"

/* UART @ 0x1000_0000. RBR/THR/DLL@0, IER/DLM@1, LCR@3 (bit7=DLAB), LSR@5 (bit5=THR empty). */
#define UART_BASE 0x10000000u
#define UART_REG(o) (*(volatile uint8_t *)(UART_BASE + (o)))
#define RBR 0
#define THR 0
#define DLL 0
#define DLM 1
#define LCR 3
#define LSR 5
#define LSR_THRE (1u << 5)   /* transmit-hold empty */

/* ------------------------------------------------------------------------- *
 * Reentrancy protection.
 *
 * uart_putc busy-waits on THR-empty. That is fine single-threaded (the bare
 * blinky used it happily), but once multiple FreeRTOS tasks AND an interrupt-
 * woken echo task all call uart_puts, two contexts can interleave mid-string:
 * task X is spinning in uart_putc when higher-priority task U preempts and
 * also enters uart_putc. The TX FIFO/THR-empty handshake then never resolves
 * for one of them and the CPU wedges in the wait loop (observed hang at the
 * TX-wait loop after a single UART interrupt).
 *
 * Fix: serialize the whole uart_puts with a FreeRTOS mutex, so a string print
 * is atomic with respect to other tasks. The mutex is created lazily on first
 * use and is only taken when the scheduler is actually running (before that,
 * e.g. the boot greeting, there is only one context so no guard is needed).
 *
 * IMPORTANT: never call uart_puts/uart_putc from an ISR — a mutex cannot be
 * taken in interrupt context. The UART echo runs in task U (a normal task),
 * not in the interrupt handler, which is what makes this safe.
 * ------------------------------------------------------------------------- */
#include "FreeRTOS.h"
#include "semphr.h"
#include "task.h"

static SemaphoreHandle_t xUartMutex = NULL;

void uart_init(uint16_t divisor) {
    UART_REG(LCR) = 0x80;                 /* DLAB=1: access divisor latch */
    UART_REG(DLL) = divisor & 0xFF;
    UART_REG(DLM) = (divisor >> 8) & 0xFF;
    UART_REG(LCR) = 0x03;                 /* 8N1, DLAB=0 */
}

void uart_putc(char c) {
    while (!(UART_REG(LSR) & LSR_THRE)) { }   /* wait until THR empty */
    UART_REG(THR) = (uint8_t)c;
}

/* Emit a string without the mutex. Used internally once the lock is held (or
 * before the scheduler starts). */
static void uart_puts_raw(const char *s) {
    while (*s) {
        if (*s == '\n') uart_putc('\r');      /* CRLF for terminals */
        uart_putc(*s++);
    }
}

void uart_puts(const char *s) {
    /* Only guard once the scheduler is running; before that we are single-
     * threaded (boot greeting) and taking a mutex would be invalid. */
    if (xTaskGetSchedulerState() == taskSCHEDULER_RUNNING) {
        if (xUartMutex == NULL) {
            /* Lazy create. If two tasks race here the loser just also creates
             * one; to keep it simple we create in a critical section. */
            taskENTER_CRITICAL();
            if (xUartMutex == NULL) xUartMutex = xSemaphoreCreateMutex();
            taskEXIT_CRITICAL();
        }
        if (xUartMutex != NULL) {
            xSemaphoreTake(xUartMutex, portMAX_DELAY);
            uart_puts_raw(s);
            xSemaphoreGive(xUartMutex);
            return;
        }
    }
    /* Fallback: scheduler not running yet, or mutex unavailable. */
    uart_puts_raw(s);
}