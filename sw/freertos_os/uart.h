#ifndef UART_H
#define UART_H
#include <stdint.h>
void uart_init(uint16_t divisor);
void uart_putc(char c);
void uart_puts(const char *s);
#endif
