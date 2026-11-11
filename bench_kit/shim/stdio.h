/* Minimal stand-in so Dhrystone builds with no libc installed (used for Dhrystone only). */
#ifndef SHIM_STDIO_H
#define SHIM_STDIO_H
#include <stddef.h>
int    printf(const char *, ...);
char  *strcpy(char *, const char *);
int    strcmp(const char *, const char *);
size_t strlen(const char *);
void  *memcpy(void *, const void *, size_t);
#endif