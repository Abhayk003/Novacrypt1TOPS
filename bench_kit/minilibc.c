/* minilibc.c -- just enough libc for CoreMark + Dhrystone, no dependencies */
#include <stddef.h>
#include <stdint.h>
#include <stdarg.h>

void plat_putc(char c);
#define NOPAT __attribute__((optimize("no-tree-loop-distribute-patterns")))

NOPAT void *memcpy(void *d, const void *s, size_t n)
{ unsigned char *a = d; const unsigned char *b = s; while (n--) *a++ = *b++; return d; }
NOPAT void *memmove(void *d, const void *s, size_t n)
{ unsigned char *a = d; const unsigned char *b = s;
  if (a < b) { while (n--) *a++ = *b++; } else { a += n; b += n; while (n--) *--a = *--b; } return d; }
NOPAT void *memset(void *d, int c, size_t n)
{ unsigned char *a = d; while (n--) *a++ = (unsigned char)c; return d; }
NOPAT int memcmp(const void *x, const void *y, size_t n)
{ const unsigned char *a = x, *b = y; while (n--) { if (*a != *b) return *a - *b; a++; b++; } return 0; }
NOPAT size_t strlen(const char *s) { const char *p = s; while (*p) p++; return (size_t)(p - s); }
NOPAT char *strcpy(char *d, const char *s) { char *r = d; while ((*d++ = *s++)) { } return r; }
NOPAT int strcmp(const char *a, const char *b)
{ while (*a && *a == *b) { a++; b++; } return (unsigned char)*a - (unsigned char)*b; }

/* modf: only needed so CoreMark's float-print helper (cvt.c) links; unused at runtime (HAS_FLOAT 0) */
double modf(double x, double *ip)
{
    if (x > -9.0e18 && x < 9.0e18) { long long i = (long long)x; *ip = (double)i; return x - *ip; }
    *ip = x; return 0.0;
}

/* bump allocator (Dhrystone mallocs two records once) */
extern char _heap_start, _heap_end;
void *malloc(size_t n)
{
    static char *p;
    char *r;
    if (!p) p = &_heap_start;
    p = (char *)(((uintptr_t)p + 15) & ~(uintptr_t)15);
    if (p + n > &_heap_end) return 0;
    r = p; p += n; return r;
}

/* minimal printf: %d %i %u %x %X %c %s %f(ints+frac) %%, flags 0, width, .prec, l/ll */
static void put_u(unsigned long long v, unsigned base, int width, char pad, int upper)
{
    char buf[24]; int i = 0;
    const char *dg = upper ? "0123456789ABCDEF" : "0123456789abcdef";
    do { buf[i++] = dg[v % base]; v /= base; } while (v);
    while (i < width && i < 23) buf[i++] = pad;
    while (i--) plat_putc(buf[i]);
}

int printf(const char *f, ...)
{
    va_list ap; va_start(ap, f);
    for (; *f; f++) {
        char pad = ' '; int width = 0, prec = -1, lng = 0;
        if (*f != '%') { plat_putc(*f); continue; }
        f++;
        if (*f == '0') { pad = '0'; f++; }
        while (*f >= '0' && *f <= '9') width = width * 10 + (*f++ - '0');
        if (*f == '.') { f++; prec = 0; while (*f >= '0' && *f <= '9') prec = prec * 10 + (*f++ - '0'); }
        while (*f == 'l') { lng++; f++; }
        switch (*f) {
        case 'd': case 'i': {
            long long v = lng >= 2 ? va_arg(ap, long long) : lng ? va_arg(ap, long) : va_arg(ap, int);
            unsigned long long u = (unsigned long long)v;
            if (v < 0) { plat_putc('-'); u = 0 - u; if (width) width--; }
            put_u(u, 10, width, pad, 0); break; }
        case 'u': case 'x': case 'X': {
            unsigned long long v = lng >= 2 ? va_arg(ap, unsigned long long)
                                 : lng ? va_arg(ap, unsigned long) : va_arg(ap, unsigned);
            put_u(v, *f == 'u' ? 10 : 16, width, pad, *f == 'X'); break; }
        case 'c': plat_putc((char)va_arg(ap, int)); break;
        case 's': { const char *s = va_arg(ap, const char *); if (!s) s = "(null)"; while (*s) plat_putc(*s++); break; }
        case 'f': {
            double v = va_arg(ap, double); unsigned long long ip; int d;
            if (v < 0) { plat_putc('-'); v = -v; }
            if (prec < 0) prec = 6;
            if (prec > 6) prec = 6;
            ip = (unsigned long long)v; v -= (double)ip;
            put_u(ip, 10, 0, ' ', 0); plat_putc('.');
            while (prec--) { v *= 10; d = (int)v; plat_putc((char)('0' + d)); v -= d; }
            break; }
        case '%': plat_putc('%'); break;
        default:  plat_putc('?'); break;
        }
    }
    va_end(ap);
    return 0;
}