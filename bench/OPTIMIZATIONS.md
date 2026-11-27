# Optimization log

How much each optimization of the elliptic-curve code delivered, one row per
step. All of them shipped in 0.3.0. Each step is a single commit, measured
with `mops bench --locked` on the toolchain pinned in `mops.toml` (moc 2.0.0
up to step 17, moc 2.2.3 from step 18 on, moc 2.2.5 from step 23 on;
pocket-ic 15.0.0, wasm-opt with `[optimize]`). The "Δ" columns compare a step
with the row above it.

Overall, compared with 0.2.2, ECDSA verification on secp256k1 takes 79.6%
fewer instructions (4.9 times faster) and allocates 67.5% less heap, and BIP32
derivation takes 80.7% fewer instructions (5.2 times faster). On curves
without GLV parameters, such as secp256r1, verification takes 44.0% fewer
instructions (1.8 times faster) and allocates 44.2% less heap. 0.2.2 measures
the same on moc 2.0.0, 2.2.3 and 2.2.5, since its code does no bignum shifts
(see step 18).

| Step                                   | ECDSA verify |      Δ | Verify heap |      Δ | BIP32 depth 5 |      Δ | `mul`, k < 2⁵⁷ |      Δ |
| :------------------------------------- | -----------: | -----: | ----------: | -----: | ------------: | -----: | -------------: | -----: |
| 0.2.2 (baseline)                       |  246_258_062 |        |   10.42 MiB |        |   737_240_050 |        |     29_830_886 |        |
| GLV endomorphism                       |  158_720_308 | −35.5% |    6.81 MiB | −34.6% |   521_699_275 | −29.2% |     29_921_334 |  +0.3% |
| Reduction specialized to secp256k1's p |  138_177_588 | −12.9% |   11.78 MiB | +73.0% |   469_896_817 |  −9.9% |     26_035_801 | −13.0% |
| Field arithmetic on `Nat` residues     |  127_092_370 |  −8.0% |   10.67 MiB |  −9.4% |   442_104_728 |  −5.9% |     23_711_013 |  −8.9% |
| Width-5 wNAF, Jacobian tables          |  116_817_125 |  −8.1% |    9.78 MiB |  −8.3% |   413_335_328 |  −6.5% |     24_593_089 |  +3.7% |
| Combined multiplication in verify      |   87_478_767 | −25.1% |    7.18 MiB | −26.6% |   412_601_208 |  −0.2% |     24_599_742 |     0% |
| Iterative field inversion              |   86_057_048 |  −1.6% |    7.11 MiB |  −1.0% |   409_007_176 |  −0.9% |     23_890_156 |  −2.9% |
| Verify without affine conversion       |   83_714_883 |  −2.7% |    6.93 MiB |  −2.5% |   409_007_176 |     0% |     23_890_156 |     0% |
| Precomputed tables for G (width 7)     |   72_794_211 | −13.0% |    5.98 MiB | −13.7% |   409_009_816 |     0% |     23_891_642 |     0% |
| Square root by addition chain          |   72_813_632 |     0% |    5.99 MiB |     0% |   320_855_562 | −21.6% |     23_865_696 |  −0.1% |
| G tables in `mul` and `mulBase`        |   72_813_572 |     0% |    5.99 MiB |     0% |   264_985_466 | −17.4% |     16_946_046 | −29.0% |
| Doubling formula for a = 0             |   68_677_192 |  −5.7% |    5.62 MiB |  −6.2% |   244_672_531 |  −7.7% |     15_302_557 |  −9.7% |
| Split G's scalar at 2⁶⁴ (width 6)      |   68_097_977 |  −0.8% |    5.65 MiB |  +0.5% |   184_148_568 | −24.7% |     16_238_213 |  +6.1% |
| Keep the field helpers private         |   68_401_510 |  +0.4% |    5.65 MiB |     0% |   185_044_210 |  +0.5% |     16_306_333 |  +0.4% |
| Retire `ec_arith` benchmark            |   68_401_510 |     0% |    5.65 MiB |     0% |   185_044_210 |     0% |     16_312_000 |     0% |
| wNAF recoding on `Nat64` words         |   60_580_051 | −11.4% |    5.24 MiB |  −7.3% |   170_790_134 |  −7.7% |     15_687_416 |  −3.8% |
| Leaner addition formulas               |   59_210_804 |  −2.3% |    5.11 MiB |  −2.5% |   167_182_713 |  −2.1% |     15_642_194 |  −0.3% |
| moc 2.2.3                              |   59_637_855 |  +0.7% |    5.11 MiB |     0% |   168_290_299 |  +0.7% |     15_738_049 |  +0.6% |
| sha2 0.3.3                             |   59_637_855 |     0% |    5.11 MiB |     0% |   168_252_199 |     0% |     15_738_049 |     0% |
| core 2.7.0                             |   59_637_855 |     0% |    5.11 MiB |     0% |   168_252_199 |     0% |     15_738_049 |     0% |
| Fold as t − hi·p                       |   50_168_009 | −15.9% |    3.39 MiB | −33.7% |   142_258_775 | −15.4% |     13_603_499 | −13.6% |
| wNAF for curves without GLV            |   50_175_402 |     0% |    3.39 MiB |     0% |   142_258_830 |     0% |     13_603_510 |     0% |
| moc 2.2.5, sha2 0.3.4, core 2.7.1      |   50_175_079 |     0% |    3.39 MiB |     0% |   142_252_190 |     0% |     13_603_510 |     0% |
| Barrett reduction for other primes     |   50_204_479 |  +0.1% |    3.39 MiB |     0% |   142_341_298 |  +0.1% |     13_611_298 |  +0.1% |
| `Field.pow` by machine words           |   50_204_473 |     0% |    3.39 MiB |     0% |   142_268_903 |  −0.1% |     13_611_609 |     0% |
| Doubling for a = −3                    |   50_204_349 |     0% |    3.39 MiB |     0% |   142_268_593 |     0% |     13_611_556 |     0% |
| Shared-Z tables for Q                  |   47_839_854 |  −4.7% |    3.24 MiB |  −4.4% |   142_127_226 |  −0.1% |     13_619_009 |  +0.1% |
| Width-8 tables for G                   |   45_511_867 |  −4.9% |    3.09 MiB |  −4.6% |   132_691_633 |  −6.6% |     13_066_187 |  −4.1% |

Starting with "Precomputed tables for G", `bench/ec_ops.bench.mo`
also measures full-size operations on secp256k1 (instructions; Δ vs the row
above):

| Step                               | Decompress |      Δ |  `mulBase` |      Δ |      `mul` |      Δ |   `mulAdd` |      Δ |
| :--------------------------------- | ---------: | -----: | ---------: | -----: | ---------: | -----: | ---------: | -----: |
| Precomputed tables for G           | 24_419_901 |        | 56_959_886 |        | 59_227_618 |        | 73_905_529 |        |
| Square root by addition chain      |  6_772_845 | −72.3% | 56_945_858 |     0% | 59_170_259 |  −0.1% | 73_853_875 |  −0.1% |
| G tables in `mul` and `mulBase`    |  6_773_162 |     0% | 45_687_955 | −19.8% | 58_969_426 |  −0.3% | 73_652_493 |  −0.3% |
| Doubling formula for a = 0         |  6_773_162 |     0% | 41_492_544 |  −9.2% | 54_834_056 |  −7.0% | 69_493_523 |  −5.6% |
| Split G's scalar at 2⁶⁴ (width 6)  |  6_773_162 |     0% | 29_150_343 | −29.7% | 55_206_258 |  +0.7% | 69_657_567 |  +0.2% |
| Keep the field helpers private     |  6_826_285 |  +0.8% | 29_273_390 |  +0.4% | 55_446_920 |  +0.4% | 69_958_715 |  +0.4% |
| wNAF recoding on `Nat64` words     |  6_826_080 |     0% | 26_491_277 |  −9.5% | 50_583_269 |  −8.8% | 62_263_255 | −11.0% |
| Leaner addition formulas           |  6_826_397 |     0% | 25_855_869 |  −2.4% | 49_925_359 |  −1.3% | 61_152_465 |  −1.8% |
| moc 2.2.3                          |  6_871_444 |  +0.7% | 26_028_224 |  +0.7% | 50_263_358 |  +0.7% | 61_574_396 |  +0.7% |
| Fold as t − hi·p                   |  5_608_775 | −18.4% | 22_187_390 | −14.8% | 42_718_644 | −15.0% | 52_144_098 | −15.3% |
| wNAF for curves without GLV        |  5_608_458 |     0% | 22_187_401 |     0% | 42_725_703 |     0% | 52_151_180 |     0% |
| moc 2.2.5, sha2 0.3.4, core 2.7.1  |  5_608_458 |     0% | 22_187_401 |     0% | 42_725_703 |     0% | 52_151_180 |     0% |
| Barrett reduction for other primes |  5_613_450 |  +0.1% | 22_200_246 |  +0.1% | 42_750_784 |  +0.1% | 52_180_855 |  +0.1% |
| `Field.pow` by machine words       |  5_598_658 |  −0.3% | 22_200_240 |     0% | 42_750_778 |     0% | 52_180_849 |     0% |
| Doubling for a = −3                |  5_598_658 |     0% | 22_200_179 |     0% | 42_750_653 |     0% | 52_180_724 |     0% |
| Shared-Z tables for Q              |  5_598_658 |     0% | 22_148_304 |  −0.2% | 38_908_267 |  −9.0% | 49_857_860 |  −4.5% |
| Width-8 tables for G               |  5_598_658 |     0% | 20_553_487 |  −7.2% | 38_951_869 |  +0.1% | 47_526_084 |  −4.7% |

Columns:

- **ECDSA verify**: instructions for `verify (preparsed)`, sample 0, in
  `bench/ecdsa_verify.bench.mo`.
- **Verify heap**: memory allocated by the same call (temporary allocation,
  not retained memory).
- **BIP32 depth 5**: instructions for deriving a depth-5 path from an array
  path in `bench/bip32.bench.mo`.
- **`mul`, k < 2⁵⁷**: instructions for multiplying G by the 57-bit scalar
  123456789123456789, including the conversion to affine. Up to step 12
  this is `mulPoint`, `k large`, in the former `bench/ec_arith.bench.mo`
  (which multiplied G); from step 13 on it is `mulBase`, `57-bit k`, in
  `bench/ec_ops.bench.mo`, the same operation. Scalars this short don't
  show gains that only apply to full-size scalars, such as GLV.
- **Decompress**: `Jacobi.fromBytes` on a compressed public key, which
  computes a square root. **`mulBase`**, **`mul`**, **`mulAdd`**: 256-bit
  scalars, including the final conversion to affine coordinates.

For reference, [motoko_ecdsa](https://github.com/edjCase/motoko_ecdsa) 8.0.2
verifies a secp256k1 signature in 110_018_892 instructions with 5.41 MiB of
heap (its own benchmark, measured without `wasm-opt`).

## Steps

The **GLV endomorphism** row comes first. secp256k1 has an efficiently
computable endomorphism φ(x, y) = (βx, y) with φ(P) = λP. `Jacobi.mul()` and
`Jacobi.mulBase()` split a scalar k into k1 + λ·k2 with k1 and k2 of about
128 bits each and compute k1·P + k2·φ(P) in one interleaved loop, which
halves the number of doublings. The parameters are in the new `Curves.Glv`
type, and `Curves.Curve` has a new field `glv : ?Glv`; curves with
`glv = null` keep the previous multiplication. 256-bit scalar
multiplications take about 34% fewer instructions. Scalars below 2¹²⁸ don't
gain (the `mul` column), as they need no more doublings than one GLV half.

1. **Reduction specialized to secp256k1's p.** Instead of `% p`, which is a
   bignum division, the bits above 2²⁵⁶ are folded back in using
   2²⁵⁶ ≡ 2³² + 977 (mod p). One modular multiplication drops from 34.7k to
   28.3k instructions. The folds allocate intermediate bignums, which is why
   the heap grows.
2. **Field arithmetic on `Nat` residues.** The point formulas used signed
   `Int` values in (−p, p) with a reduction after nearly every operation,
   including products of three values (768 bits). Now every coordinate is a
   canonical residue in [0, p): products are reduced with a fixed two-pass
   fold, and additions and subtractions use a conditional add or subtract of
   p instead of a reduction. The formulas are unchanged. This also makes the
   doubling checks in the addition formulas exact: with signed values, a
   difference congruent to 0 but equal to ±p wasn't recognized.
3. **Width-5 wNAF, Jacobian tables.** The GLV loop used width-2 NAF digits,
   so on average one digit in three needed a point addition. Now each half
   scalar is written in width-5 NAF (one addition per six digits, about 43
   per half instead of about 86), against a table of the odd multiples
   P, 3P, …, 15P and their images under the endomorphism. The tables stay in
   Jacobian coordinates, so each addition is a full addition rather than the
   cheaper mixed one. Building the tables costs one doubling and seven
   additions per multiplication, which is why short scalars (the `mul`
   column) get slower. Widths 4 and 6 measured 118.6M and 119.0M for verify.

4. **Combined multiplication in verify.** ECDSA verification computes
   u1·G + u2·Q. Instead of two separate GLV multiplications, the new
   `Jacobi.mulAdd()` runs one interleaved wNAF loop over all four
   half-length scalars, so the two multiplications share one set of about
   129 doublings instead of needing about 258. BIP32 derivation and `mul`
   are single multiplications and don't change.

5. **Iterative field inversion.** `Field.inverse` used a recursive extended
   Euclidean algorithm on `Int` that performed two bignum divisions per step
   and tracked both Bézout coefficients. The iterative version does one
   division per step and tracks only the coefficient it returns: one
   inversion mod p drops from 3.14M to 2.44M instructions. Verify does two
   (s⁻¹ mod n and the final conversion to affine coordinates). A binary GCD
   (shifts and subtractions only) measured 18.6M, six times slower, because
   it needs many more bignum operations.

6. **Verify without affine conversion.** Verify converted the sum
   u1·G + u2·Q to affine coordinates, which costs one field inversion, only
   to compare its x with r. Since x = X/Z² < p < 2n, x mod n == r means
   x == r, or x == r + n when r + n < p. Verify now compares X with r·Z²
   (and with (r + n)·Z² in the rare second case) instead. Wycheproof's
   "k*G has a large x-coordinate" vector covers the second case: the test
   fails if it is removed.

7. **Precomputed tables for G.** Verify built the wNAF tables for G and
   φ(G) on every call. They are now constants in
   `src/ec/Secp256k1Generator.mo`, generated by
   `scripts/secp256k1_generator_table.py`. Being constant, they are affine
   (so G's digits use mixed additions) and can use a wider window than the
   per-call tables of Q (width 5). `Jacobi.mulAdd` uses them for any input
   point that is the secp256k1 generator. `mul` and `mulBase` don't use
   them yet.

   Large `Nat` literals aren't static data: moc emits code that builds each
   bignum, about 160–260 bytes of Wasm per `Nat` against 32 bytes of value.
   That code runs in the Wasm start function, which the IC executes when it
   instantiates the module: at install, reinstall and every upgrade (with
   enhanced orthogonal persistence the tables are rebuilt after each
   upgrade). It is charged to that operation, not to later messages, and not
   to the first use of the curve. Evidence:

   - The canister Wasm has a start section.
   - `Prim.performanceCounter(0)` read in the actor initializer showed the
     same 5_198 instructions with no table, 16 points and 64 points, so the
     work is not in the counted part of `canister_init`.
   - Inside one message, the first pass over the table cost exactly as much
     as the second (674_821 instructions at width 5), so construction is not
     lazy.
   - A WASI build, which runs everything from `_start`, needed more wasmtime
     fuel as the table grew (the "Init" column below). Fuel is roughly one
     unit per Wasm instruction, close to but not identical to the IC's count;
     the init cost wasn't measured on a replica.

   Measured on a canister that calls `Ecdsa.verify` (242_950 bytes after
   `wasm-opt -O3` without the tables):

   | Width | Points |        Wasm (-O3) | Init (once) | ECDSA verify | Δ vs no table |
   | ----: | -----: | ----------------: | ----------: | -----------: | ------------: |
   |     5 |     16 |   +5.4 KB (+2.2%) |    about 5k |   76_459_061 |         −8.7% |
   |     6 |     32 |  +10.8 KB (+4.4%) |   about 10k |   74_104_636 |        −11.5% |
   |     7 |     64 |  +21.4 KB (+8.8%) |   about 20k |   72_794_211 |        −13.0% |
   |     8 |    128 | +42.5 KB (+17.5%) |   about 39k |   71_661_465 |        −14.4% |

   Width 7 is the chosen trade-off. To change it, regenerate the module with
   another width; nothing else depends on it.

8. **Square root by addition chain.** Decompressing a public key computes
   a square root, a^((p+1)/4), through `Fp.sqrt()` and `Field.pow`, which
   still used the generic `% p` for each of about 500 multiplications
   (253 squarings and 246 multiplications by square-and-multiply). Now
   `Field.mul` uses the secp256k1 fold when the modulus is p and the
   product is below 2⁵¹² (so its contract, `(a * b) % n` for any inputs,
   is unchanged), and `Fp.sqrt()` uses an addition chain of 253 squarings
   and 13 multiplications (the one in libsecp256k1). The fold moved from
   `Jacobi` to `Field.reduceSecp256k1`, shared by both. Decompression
   drops by 72%. Verifying against a compressed public key, which goes
   through the same decompression in `Publickey.decode`, saves the same
   17.6M; `bench/ecdsa_verify.bench.mo` uses a parsed key and doesn't show
   it.

9. **G tables in `mul` and `mulBase`.** `mul` now uses the precomputed
   tables of step 7 whenever its point is the secp256k1 generator, like
   `mulAdd` already did, so `mulBase` no longer builds G's tables on every
   call and its additions are mixed additions with width 7. This speeds up
   BIP32 derivation and signing. `mul` on other points is unchanged. The
   `mul`, k < 2⁵⁷ column drops too, because that benchmark multiplies G.

10. **Doubling formula for a = 0.** On secp256k1 a = 0, but the doubling
    still computed Z², and it formed Z3 as (Y + Z)² − YY − ZZ and S as
    2((X + YY)² − XX − YYYY). The new formula (dbl-2009-l) computes
    S = 4·X·YY and Z3 = 2·Y·Z directly and skips Z² unless a ≠ 0: seven
    multiplications instead of eight, and four fewer subtractions. With
    bignums a multiplication costs about as much as a squaring, so the
    squaring tricks only added work. Every full-size multiplication does
    about 129 doublings, so this shows up everywhere.

11. **Split G's scalar at 2⁶⁴.** A multiple of G needs as many doublings as
    its longest wNAF term, about 129 for the GLV halves of a 256-bit
    scalar. Each GLV half k is now split once more into
    k_low + 2⁶⁴·k_high, against precomputed tables of G, H = 2⁶⁴·G, φ(G)
    and φ(H). The four pieces have about 65 digits, so `mulBase` needs
    about 65 doublings instead of 129 and roughly the same number of
    additions. This speeds up BIP32 public key derivation and Taproot key
    tweaking, the two callers of `mulBase` in the library. (The library
    doesn't sign locally: `Bitcoin.mo` signs through an `EcdsaProxy`, for
    example the IC's threshold ECDSA.) Verify doesn't gain doublings,
    because Q's two terms still have 129 digits.

    Four tables cost twice the literals of two, so the tables now use
    width 6: four tables of 16 points each, 64 points in total, the same
    count as the two width-7 tables of step 7. Measured against step 10
    (canister calling `Ecdsa.verify` and `mulBase`, Wasm after
    `wasm-opt -O3`; init cost with wasmtime fuel):

    | Tables      | Points |             Wasm | Init (once) |  `mulBase` |     Verify | BIP32 depth 5 |
    | :---------- | -----: | ---------------: | ----------: | ---------: | ---------: | ------------: |
    | 2 × width 7 |     64 |        266_539 B |   about 34k | 41_492_544 | 68_677_192 |   244_672_531 |
    | 4 × width 6 |     64 |   +684 B (+0.3%) |       +0.4k | 29_150_343 | 68_097_977 |   184_148_568 |
    | 4 × width 7 |    128 | +21.8 KB (+8.2%) |        +34k | 27_227_307 | 66_811_099 |   177_534_723 |

    Width 6 is better than before on every full-size benchmark at the same
    size. Scalars below 2⁶⁴ don't benefit (their high pieces are zero) and
    pay a few more additions for the narrower window: the `mul`, k < 2⁵⁷
    column, which multiplies G, gets 6.1% slower.

    The init figures here are for the `(x, y, 1)` triples of the committed
    module and replace the earlier estimate for step 7 (about 20k), which
    was measured with `(x, y)` pairs.

12. **Keep the field helpers private.** Steps 8–11 had made
    `Field.secp256k1P`, `Field.reduceSecp256k1` and `Field.sqrtSecp256k1`
    public so that `Jacobi` and `Fp` could share them. To keep them out of
    the published API, the fold is now private to `Field` and used through
    `Field.mul`, and the square-root chain is private to `Fp`.
    `Secp256k1Generator` has to stay a public module (Motoko has no
    package-private modules) and is documented as internal. Going through
    `Field.mul` costs `Jacobi` an extra `t < 2⁵¹²` check and a cross-module
    call per multiplication: about +0.4% everywhere. A private copy of the
    fold in `Jacobi` would avoid that, at the price of a second copy of the
    same code.

13. **Retire the `ec_arith` benchmark.** Its scalars were all below 2⁵⁷,
    so it misrepresented every full-size change (it showed +6.1% for the 2⁶⁴
    split, which made `mulBase` 30% faster), and its `mulPoint` row
    multiplied G, so it measured `mulBase` twice. `bench/ec_ops.bench.mo`
    now has a `57-bit k` column with the same scalar next to the `256-bit k`
    column; its `mulBase` cell matches the old `k large` cell (16_312_000 vs
    16_311_884). No code change.

14. **wNAF recoding on `Nat64` words.** Found by comparing with
    [motoko_ecdsa#4](https://github.com/research-ag/motoko_ecdsa/pull/4),
    which verifies in 66.1M instructions despite still converting the result
    to affine and validating the public key on every call. Its primitives
    cost about the same as ours, except the recoding: `Numbers.toWnaf` did a
    bignum `%` and `/` for every digit position, about 2.56M instructions
    for a 128-bit scalar, as much as 13 doublings. Verify recodes six
    scalars (Q's two GLV halves and G's four pieces). motoko_ecdsa skips a
    whole window after each non-zero digit and took 1.25M. Now `toWnaf`
    splits |n| into 64-bit words once and runs libsecp256k1's recoding on
    `Nat64` values: 61.5k instructions for a 128-bit scalar, 42 times
    faster. The output is unchanged (the width-w NAF of a number is
    unique; checked against the old algorithm on more than 4,000 inputs and
    widths). Widths above 32 keep the bignum algorithm.

15. **Leaner addition formulas.** Also from the comparison with
    motoko_ecdsa. Our mixed and full additions (madd-2007-bl and
    add-2007-bl) scale by 2 to save multiplications that only pay off when
    a squaring is much cheaper than a multiplication: `I = 4·HH`,
    `r = 2(S2 − S1)`, `2·V`, `2·Y1·J` and `Z3 = (Z1 + H)² − Z1Z1 − HH`. With
    bignums a squaring costs about as much as a multiplication, so the H³
    form, with the same 11 (mixed) and 16 (full) multiplications and about
    half the additions and subtractions, is cheaper: measured in isolation,
    a mixed addition 302.8k → 282.4k and a full one 423.2k → 403.7k
    instructions. When H = 0 and r ≠ 0 (P2 = −P1) the formulas now return
    the point at infinity directly.

16. **Guard the projective verify check.** Found by CodeRabbit's review of
    research-ag/motoko-bitcoin#16. Step 6's comparison of X with r·Z² and
    (r + n)·Z² is equivalent to x mod n == r only if n < p < 2n, which
    secp256k1 satisfies. `Curves.Curve` is a public type, and on other
    curves the check was wrong in both directions: with n > p it accepted
    signatures with r ≥ p (because `curve.Fp(r)` reduces r mod p), and with
    p > 2n it rejected valid signatures whose x is r + 2n or more. Verify
    now uses the projective check only if n < p < 2n and otherwise converts
    to affine as before. A test checks every (r, s) on two toy curves
    (p = 5, n = 7 and p = 13, n = 5) against results computed directly; it
    fails with the guard removed. Cost on secp256k1: 3_439 instructions per
    verify (+0.006%).

17. **secp256r1 in the tests and benchmarks.** secp256r1 (NIST P-256) is
    defined in `test/ec/Secp256r1.mo`, for tests and benchmarks only; the
    package doesn't export it. It has no GLV endomorphism and a = −3, so it
    exercises the generic code paths that secp256k1 never takes. The tests
    run all 484 Wycheproof secp256r1 vectors (converted by
    `scripts/wycheproof_ecdsa_to_motoko.py` from the C2SP/wycheproof v1
    files); vectors flagged `MissingZero` (a legacy DER encoding that the
    decoder accepts) count as acceptable, as in the older secp256k1 file.
    `bench/ecdsa_verify.bench.mo` and `bench/ec_ops.bench.mo` have a
    secp256r1 column. Baseline on the generic paths: verify 260_500_021
    instructions (11.31 MiB), `mulBase` 130_937_616, `mul` 133_063_220,
    `mulAdd` 261_322_479, decompression 15_896_705. For comparison,
    motoko_ecdsa#4 verifies on P-256 in 122.8M, with Montgomery
    multiplication, wNAF and Shamir's trick for that curve. No code change;
    the secp256k1 numbers are unchanged.

18. **moc 2.2.3.** The toolchain moves from moc 2.0.0 to 2.2.3, which makes
    every secp256k1 operation about 0.7% slower; secp256r1 doesn't change.
    moc 2.2.0 and 2.2.2 fixed wrong results of `Prim.shiftLeft` and
    `Prim.shiftRight` on `Nat` for large results and shift amounts
    (motoko#6447, #6423), and the added checks make each bignum shift more
    expensive: 49 instructions more for a right shift and 56 more for a left
    shift, measured on 256- and 512-bit operands. Multiplication, addition,
    subtraction, comparison and `% p` cost the same as before. Nearly all
    shifts come from the secp256k1 reduction in `Field.mul`, two in each
    direction per multiplication, which is why secp256r1, which reduces with
    `% p`, is unaffected. Counted in an instrumented run, `mulAdd` performs
    4_138 right and 4_130 left shifts, which predicts +434k instructions; it
    measured +422k. The rest of moc 2.2.x saves a little elsewhere (a
    `switch` on a tuple no longer allocates, and boxed `Nat64` values are
    smaller): the non-EC benchmarks got up to 1% cheaper and allocate up to
    5% less. No code change. moc 2.2.3 itself only changes Candid decoding
    and measures the same as 2.2.2.

19. **sha2 0.3.3.** Updating the `sha2` dependency from 0.3.0 to 0.3.3
    makes HMAC-SHA256 4–8% and HMAC-SHA512 5–10% cheaper
    (`bench/hash_hmac.bench.mo`, longer inputs gain more). BIP32 derivation
    hashes little compared with its elliptic-curve work and saves 38k
    instructions at depth 5 (−0.02%); Base58Check and transaction sighashes
    save up to 1%. The elliptic-curve benchmarks don't use SHA-2 and don't
    change. sha2 0.3.3 declares core 2.7.0; the package still compiled
    against core 2.6.2 in this step.

20. **core 2.7.0.** Updating the `core` dependency from 2.6.2 to 2.7.0
    changes none of the 188 benchmark cells, instructions or heap.

21. **Fold as t − hi·p.** Each of the two folds in the secp256k1 reduction
    computed hi = t >> 256, lo = t − (hi << 256) and lo + hi·(2³² + 977):
    a shift, a subtraction, a small multiplication and an addition, each of
    which allocates a new bignum. Since 2²⁵⁶ − (2³² + 977) = p, the same
    value is t − hi·p: one multiplication and one subtraction. The result
    is identical, and the bound after two folds is unchanged
    (below 2²⁵⁶ + 2⁶⁷ < 2p). Per `Field.mul` this saves about 4.7k
    instructions and 0.9 KiB of heap (from decompression, about 270
    multiplications), and it removes the two left shifts that moc 2.2.x
    made more expensive (step 18). Every secp256k1 operation is 13–18%
    cheaper and allocates 28–39% less; secp256r1 reduces with `% p` and
    doesn't change.

22. **wNAF for curves without GLV.** Curves with `glv = null` (every user-defined `Curve`, and
    secp256r1 in the tests) multiplied with width-2 NAF, about one addition
    per three bits, and `mulAdd` fell back to two separate multiplications
    plus an addition, so ECDSA verification did 512 doublings. Now they use
    the same `wnafSum` loop as secp256k1, with one term per scalar: width-5
    wNAF against a table of the odd multiples P, 3P, …, 15P (one doubling
    and seven additions to build), and `mulAdd` shares one doubling per bit
    between both scalars. There are no precomputed generator tables for
    these curves, and the field reduction is still `% p`. On secp256r1:
    verify 260_500_021 → 141_756_826 instructions (−45.6%) and 11.31 →
    6.11 MiB of heap (−46.0%); `mulAdd` −44.1%; `mul` and `mulBase` −9.9%.
    secp256k1 doesn't change. Tests check `mul`, `mulBase` and `mulAdd`
    against double-and-add on secp256r1, on secp256k1 with its GLV
    parameters removed, and exhaustively on two small curves of prime order
    (5 and 13), where table entries and sums reach the point at infinity.

23. **moc 2.2.5, sha2 0.3.4, core 2.7.1.** Updating the toolchain and both
    dependencies changes no benchmark by more than 0.01%. On secp256r1,
    verify measures 141_771_116 instructions, against 252_959_189 in 0.2.2
    (−44.0%).

24. **Barrett reduction for other primes.** Field multiplications for any
    prime other than secp256k1's reduced the product with `% p`, a bignum
    division. They now use Barrett reduction (`Field.mulMod`): two
    multiplications by precomputed constants, two shifts and at most two
    subtractions. `Field.modulus(p)` computes the constants once per
    operation (about one division) and `Jacobi` passes them down. They are
    a tuple because a record's fields are looked up by hash at runtime: as
    a record, secp256k1 lost 0.3%, as a tuple 0.05%. `Field.pow` uses it
    too. On secp256r1: verify 141_771_116 → 101_067_334 instructions
    (−28.7%); `mulAdd` −28.3%, `mul` −28.0%, `mulBase` −28.4%,
    decompression −17.6%. Heap changes by less than 1%: the temporaries of
    Barrett reduction take about as much as the division's. secp256k1
    doesn't change (+0.06%).

25. **`Field.pow` by machine words.** `Field.pow` built the exponent's bits
    with `Numbers.toBinaryReversed`, one bignum `% 2` and `/ 2` per bit and
    a `List` of `Bool`s: 6.3M of the 12.3M instructions of a square root on
    secp256r1, more than the 255 squarings themselves. It now splits the
    exponent into 64-bit words and tests the bits of each word with `Nat64`
    operations. Square roots on secp256k1 use an addition chain and don't
    call `pow`. On secp256r1: decompression 13_091_612 → 6_737_983
    instructions (−48.5%), heap 693 → 389 KiB (−43.9%). Decompression on
    secp256k1 gets 0.3% cheaper (the `x.pow(3)` in the curve equation);
    everything else changes by at most 0.05%.

26. **Doubling for a = −3.** For a ≠ 0, doubling computed M = 3·X² + a·Z⁴
    with three squarings and a multiplication by a. For a = −3, which
    secp256r1 and the other NIST curves use, M = 3·(X − Z²)·(X + Z²): one
    squaring and one multiplication. `doDouble` checks `a + 3 == p`. On
    secp256r1: verify 101_067_328 → 91_205_243 instructions (−9.8%), heap
    6.09 → 5.59 MiB (−8.2%); `mul` −11.5%, `mulBase` −11.8%, `mulAdd`
    −9.5%. secp256k1 doesn't change (+0.01%).

27. **Shared-Z tables for Q.** The table of odd multiples of a point Q
    that isn't the generator had a different Z per entry, so each addition
    in the main loop was a full addition (11M + 5S). The table is now built
    as in libsecp256k1, without an inversion: 2Q first, the other entries
    by mixed additions on the isomorphic curve on which 2Q is affine, and a
    backward pass that brings all of them to one shared Z. On curves with
    a = 0 the main loop then runs on the isomorphic curve on which those
    entries are affine, so they take a mixed addition (8M + 3S); the
    affine generator tables have Z = 1/zg there, which costs one extra
    multiplication per addition (libsecp256k1's `gej_add_zinv_var`, now a
    parameter of the mixed addition). `mul` −9.0%, `mulAdd` −4.5%, verify
    −4.7%; `mulBase` and BIP32 derivation don't change. A first version
    that also rescaled the table of a second non-generator point, used a
    separate copy of the loop for `mulBase` and a separate addition for
    the generator tables saved 0.6–0.7% more, with 179 instead of 85 added
    lines. Lazy reduction was measured first and not adopted: in one
    `mulAdd`, 1_075 of 2_171 field additions and subtractions take the
    extra subtraction, at most 3.5% of the instructions, and because the
    secp256k1 prime is so close to 2²⁵⁶ only a bound of 2p would save a
    part of that, at the cost of extra checks at every equality test.

28. **Width-8 tables for G.** Steps 11–27 made everything except the
    digits of G cheaper, so a wider window for the four precomputed G
    tables pays more than at step 11. The tables grow from 16 to 64 points
    each, regenerated with `scripts/secp256k1_generator_table.py 8`.
    Measured against step 27 (canister calling `Jacobi.mulBase` on
    secp256k1, Wasm after `wasm-opt -O3`):

    | Tables      | Points |              Wasm |  `mulBase` |     Verify | BIP32 depth 5 |
    | :---------- | -----: | ----------------: | ---------: | ---------: | ------------: |
    | 4 × width 6 |     64 |         205_548 B | 22_148_304 | 47_839_854 |   142_127_226 |
    | 4 × width 7 |    128 | +21.1 KB (+10.3%) | 20_692_855 | 46_786_729 |   137_135_090 |
    | 4 × width 8 |    256 | +63.4 KB (+30.8%) | 20_553_487 | 45_511_867 |   132_691_633 |

    Width 8: verify −4.9%, heap −4.6%; `mulAdd` −4.7%, `mulBase` −7.2%,
    BIP32 depth 5 −6.6%. `mul` of a point other than G doesn't change
    (+0.1%). `mulBase` with a 57-bit scalar gains less (−4.1%, width 7:
    −4.7%), as its high pieces are zero.

    The tables are not static data: moc builds them with code that runs
    when the module is initialized, at install and at every upgrade, so
    the whole size increase is in the code section. That code costs
    about 11k instructions at width 6 and 40k at width 8 (wasmtime fuel
    of a WASI program that only imports the module), and the tables keep
    about 3.8 KiB (width 6) or 15.0 KiB (width 8) of heap for the
    lifetime of the canister.

## Tried and not adopted

- **Affine wNAF tables** (after step 3). Converting each table to affine
  coordinates with one batched inversion (Montgomery's trick) lets the main
  loop use mixed additions again. But one inversion via the extended
  Euclidean algorithm costs about 3.7M instructions, as much as the mixed
  additions save: verify measured 117_561_742 (+0.6%), BIP32 depth 5
  412_244_576 (−0.3%), and `mul` with a short scalar got 38% slower.

  Retried after step 6, with the faster inversion: verify 83_714_883 →
  82_803_498 (−1.1%), heap 6.93 → 6.81 MiB, BIP32 depth 5 409_007_176 →
  404_596_448 (−1.1%), but `mul` with scalars below 2⁵⁷ got 9.5–34% slower.
  Dropped: the gain is too small for the extra code. Only width 5 was
  measured. Affine tables come for free in a precomputed table for G,
  because its entries are constants.

- **Other wNAF widths for Q** (after step 27). With shared-Z tables, the
  table of a point other than the generator is cheaper to build, so a wider
  window looked worthwhile. It isn't: a GLV half has only about 128 bits, so
  doubling the table costs more than the few additions it saves. Against
  width 5, on secp256k1: width 6 verify +3.3%, `mul` +6.0%, `mulAdd` +3.3%;
  width 7 verify +15.4%, `mul` +19.0%; width 4 verify +0.5%, `mul` +3.0%,
  but `mul` with a 57-bit scalar −6.0%. Width 5 stays.
