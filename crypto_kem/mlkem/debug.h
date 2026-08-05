#ifndef DEBUG_H
#define DEBUG_H

#include <stdio.h>
#include <stdint.h>
#include "params.h"
#include "poly.h"
#include "polyvec.h"

static inline void print_hex(const char *name,
                             const uint8_t *buf,
                             size_t len)
{
    size_t i;
    printf("%s[%zu] = ", name, len);

    for(i = 0; i < len; i++) {
        printf("%02x", buf[i]);
    }

    printf("\n");
}

static inline void print_poly(const char *name, const poly *p)
{
    size_t i;

    printf("%s = [", name);

    for(i = 0; i < KYBER_N; i++) {
        printf("%d", p->coeffs[i]);

        if(i != KYBER_N - 1)
            printf(", ");
    }

    printf("]\n");
}

static inline void print_polyvec(const char *name, const polyvec *v)
{
    size_t i;
    char tmp[128];

    for(i = 0; i < KYBER_K; i++) {
        snprintf(tmp, sizeof(tmp), "%s[%zu]", name, i);
        print_poly(tmp, &v->vec[i]);
    }
}

#endif
