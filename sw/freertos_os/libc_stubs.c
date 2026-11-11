/* libc_stubs.c - minimal C library functions the FreeRTOS kernel needs,
 * since we build with -nostdlib. Provides mem* used by tasks.c/queue.c/heap_4.c. */
#include <stddef.h>

void *memset( void *s, int c, size_t n )
{
    unsigned char *p = (unsigned char *)s;
    while( n-- ) *p++ = (unsigned char)c;
    return s;
}

void *memcpy( void *d, const void *s, size_t n )
{
    unsigned char *dp = (unsigned char *)d;
    const unsigned char *sp = (const unsigned char *)s;
    while( n-- ) *dp++ = *sp++;
    return d;
}

void *memmove( void *d, const void *s, size_t n )
{
    unsigned char *dp = (unsigned char *)d;
    const unsigned char *sp = (const unsigned char *)s;
    if( dp < sp ) { while( n-- ) *dp++ = *sp++; }
    else { dp += n; sp += n; while( n-- ) *--dp = *--sp; }
    return d;
}

int memcmp( const void *a, const void *b, size_t n )
{
    const unsigned char *pa = a, *pb = b;
    while( n-- ) { if( *pa != *pb ) return *pa - *pb; pa++; pb++; }
    return 0;
}

size_t strlen( const char *s )
{
    const char *p = s;
    while( *p ) p++;
    return (size_t)(p - s);
}

char *strcpy( char *d, const char *s )
{
    char *r = d;
    while( ( *d++ = *s++ ) );
    return r;
}

char *strncpy( char *d, const char *s, size_t n )
{
    char *r = d;
    while( n && ( *d++ = *s++ ) ) n--;
    while( n-- ) *d++ = 0;
    return r;
}
