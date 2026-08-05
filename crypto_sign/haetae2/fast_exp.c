#include "fast_exp_asm.h"
#include "fixpoint.h"

fp63_48 haetae_approx_exp_asm(const fp63_48 x){
    int64_t result;
    result = -0x0000B6C6340925AELL;
    result = ((smulh48(result, x) + (1LL << 2)) >> 3) + 0x0000B4BD4DF85227LL;
    result = ((smulh48(result, x) + (1LL << 2)) >> 3) - 0x0000887F727491E2LL;
    result = ((smulh48(result, x) + (1LL << 1)) >> 2) + 0x0000AAAA643C7E8DLL;
    result = ((smulh48(result, x) + (1LL << 1)) >> 2) - 0x0000AAAAA98179E6LL;
    result = ((smulh48(result, x) + 1LL) >> 1) + 0x0000FFFFFFFB2E7ALL;
    result = ((smulh48(result, x) + 1LL) >> 1) - 0x0000FFFFFFFFF85FLL;
    result = ((smulh48(result, x))) + 0x0000FFFFFFFFFFFCLL;
    return (fp63_48)result;

}


