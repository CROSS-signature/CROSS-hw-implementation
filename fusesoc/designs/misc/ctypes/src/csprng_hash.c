/**
 *
 * Reference ISO-C11 Implementation of CROSS.
 *
 * @version 2.0 (February 2025)
 *
 * Authors listed in alphabetical order:
 *
 * @author: Alessandro Barenghi <alessandro.barenghi@polimi.it>
 * @author: Marco Gianvecchio <marco.gianvecchio@mail.polimi.it>
 * @author: Patrick Karl <patrick.karl@tum.de>
 * @author: Gerardo Pelosi <gerardo.pelosi@polimi.it>
 * @author: Jonas Schupp <jonas.schupp@tum.de>
 *
 *
 * This code is hereby placed in the public domain.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHORS ''AS IS'' AND ANY EXPRESS
 * OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHORS OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
 * BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 * OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
 * EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 **/

#include <string.h>
#include <stdlib.h>

#include "csprng_hash.h"

CSPRNG_STATE_T platform_csprng_state;

#define  POSITION_MASK (( (uint16_t)1 << BITS_TO_REPRESENT(T-1))-1)

/* Fisher-Yates shuffle obtaining the entire required randomness in a single
 * call */
void expand_digest_to_fixed_weight(uint8_t fixed_weight_string[T],
                                   const uint8_t digest[HASH_DIGEST_LENGTH]){

    /* explicit domain separation with unique integer */
    const uint16_t dsc_csprng_b = CSPRNG_DOMAIN_SEP_CONST + (3*T);

    CSPRNG_STATE_T csprng_state;
    csprng_initialize(&csprng_state, digest, HASH_DIGEST_LENGTH, dsc_csprng_b);
    uint8_t CSPRNG_buffer[ROUND_UP(BITS_CWSTR_RNG,8)/8];
    csprng_randombytes(CSPRNG_buffer,ROUND_UP(BITS_CWSTR_RNG,8)/8,&csprng_state);

    /* initialize CW string */
    memset(fixed_weight_string,1,W);
    memset(fixed_weight_string+W,0,T-W);

    uint64_t sub_buffer = 0;
    for (int i=0; i<8; i++) {
        sub_buffer |= ((uint64_t) CSPRNG_buffer[i]) << 8*i;
    }
    int bits_in_sub_buf = 64;
    int pos_in_buf = 8;
    int pos_remaining = sizeof(CSPRNG_buffer) - pos_in_buf;

    int curr = 0;
    while(curr < T) {
        /* refill randomness buffer if needed */
        if (bits_in_sub_buf <= 32 && pos_remaining > 0) {
            /* get at most 4 bytes from buffer */
            int refresh_amount = (pos_remaining >= 4) ? 4 : pos_remaining;
            uint32_t refresh_buf = 0;
            for (int i=0; i<refresh_amount; i++) {
                refresh_buf |= ((uint32_t)CSPRNG_buffer[pos_in_buf+i]) << 8*i;
            }
            pos_in_buf += refresh_amount;
            sub_buffer |=  ((uint64_t) refresh_buf) << bits_in_sub_buf;
            bits_in_sub_buf += 8*refresh_amount;
            pos_remaining -= refresh_amount;
        }
        /*we need to draw a number in 0... T-1-curr */
        int bits_for_pos = BITS_TO_REPRESENT(T-1-curr);
        uint64_t pos_mask = ( (uint64_t) 1 <<  bits_for_pos) - 1;
        uint16_t candidate_pos = (sub_buffer & pos_mask);
        if (candidate_pos < T-curr) {
            int dest = curr+candidate_pos;
            /* the position is admissible, swap */
            uint8_t tmp = fixed_weight_string[curr];
            fixed_weight_string[curr] = fixed_weight_string[dest];
            fixed_weight_string[dest] = tmp;
            curr++;
        }
        sub_buffer = sub_buffer >> bits_for_pos;
        bits_in_sub_buf -= bits_for_pos;
    }
} /* expand_digest_to_fixed_weight */

/* Test functions for cocotb */
FZ_ELEM* test_zz_vec(uint8_t *seed) {

    CSPRNG_STATE_T csprng_state;
    uint16_t dsc = 0;
    csprng_initialize(&csprng_state, seed, SEED_LENGTH_BYTES, dsc);

#ifdef RSDP
    FZ_ELEM *res = malloc(N*sizeof(FZ_ELEM));
    csprng_fz_vec(res, &csprng_state);
#elif RSDPG
    FZ_ELEM *res = malloc(M*sizeof(FZ_ELEM));
    csprng_fz_inf_w(res, &csprng_state);
#endif
    return res;
}

uint8_t* test_vt_w_mat(uint8_t *seed) {

    CSPRNG_STATE_T csprng_state;
    uint16_t dsc = 3*T+2;
    csprng_initialize(&csprng_state, seed, KEYPAIR_SEED_LENGTH_BYTES, dsc);

    FP_ELEM tmp_vt[K][N-K];

#ifdef RSDP
    csprng_fp_mat(tmp_vt,&csprng_state);
    uint8_t *res = malloc(K*(N-K)*sizeof(FP_ELEM));
    memcpy(res, tmp_vt, K*(N-K)*sizeof(FP_ELEM));
#elif RSDPG
    FZ_ELEM tmp_w[M][N-M];
    csprng_fz_mat(tmp_w,&csprng_state);
    csprng_fp_mat(tmp_vt,&csprng_state);

    uint8_t *res = malloc(K*(N-K)*sizeof(FP_ELEM)+ M*(N-M)*sizeof(FZ_ELEM));
    memcpy(res, tmp_vt, K*(N-K)*sizeof(FP_ELEM));
    memcpy(res+K*(N-K)*sizeof(FP_ELEM), tmp_w, M*(N-M)*sizeof(FZ_ELEM));
#endif

    return res;
}

FP_ELEM* test_beta_vec(uint8_t *seed) {

    CSPRNG_STATE_T csprng_state;
    uint16_t dsc = 3*T-1;
    csprng_initialize(&csprng_state, seed, HASH_DIGEST_LENGTH, dsc);

    FP_ELEM *res = malloc(T*sizeof(FP_ELEM));
    csprng_fp_vec_chall_1(res, &csprng_state);
    return res;
}

uint8_t* test_zz_zq_vecs(uint8_t *seed) {

    CSPRNG_STATE_T csprng_state;
    uint16_t dsc = 0;
    csprng_initialize(&csprng_state, seed, SEED_LENGTH_BYTES, dsc);

    FP_ELEM fq_res[N];

#ifdef RSDP
    FZ_ELEM fz_res[N];
    uint8_t *res = malloc(N*sizeof(FZ_ELEM)+N*sizeof(FP_ELEM));

    csprng_fz_vec(fz_res, &csprng_state);
    csprng_fp_vec(fq_res, &csprng_state);

    memcpy(res, fz_res, N*sizeof(FZ_ELEM));
    memcpy(res+N*sizeof(FZ_ELEM), fq_res, N*sizeof(FP_ELEM));
#elif RSDPG
    FZ_ELEM fz_res[M];
    uint8_t *res = malloc(M*sizeof(FZ_ELEM)+N*sizeof(FP_ELEM));

    csprng_fz_inf_w(fz_res, &csprng_state);
    csprng_fp_vec(fq_res, &csprng_state);

    memcpy(res, fz_res, M*sizeof(FZ_ELEM));
    memcpy(res+M*sizeof(FZ_ELEM), fq_res, N*sizeof(FP_ELEM));
#endif
    return res;
}

uint8_t* test_b_vec(uint8_t *seed) {

    uint8_t *res = malloc(T*sizeof(uint8_t));
    memset(res, 0, T*sizeof(uint8_t));
    memset(res, 1, W*sizeof(uint8_t));
    expand_digest_to_fixed_weight(res, seed);
    return res;
}
