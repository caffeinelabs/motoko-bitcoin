# Optimization log

How much each optimization of the elliptic-curve code delivered, one row per
step. Each step is a single commit, measured with `mops bench --locked` on
the toolchain pinned in `mops.toml` (moc 2.0.0, pocket-ic 15.0.0, wasm-opt
with `[optimize]`). The "Δ" columns compare a step with the row above it.

| Step                                   | ECDSA verify |      Δ | Verify heap |      Δ | BIP32 depth 5 |     Δ | `mul`, k < 2⁵⁷ |      Δ |
| :------------------------------------- | -----------: | -----: | ----------: | -----: | ------------: | ----: | -------------: | -----: |
| 0.2.3 (GLV, `% p`)                     |  158_720_308 |        |    6.81 MiB |        |   521_699_275 |       |     29_921_334 |        |
| Reduction specialized to secp256k1's p |  138_177_588 | −12.9% |   11.78 MiB | +73.0% |   469_896_817 | −9.9% |     26_035_801 | −13.0% |
| Field arithmetic on `Nat` residues     |  127_092_370 |  −8.0% |   10.67 MiB |  −9.4% |   442_104_728 | −5.9% |     23_711_013 |  −8.9% |
| Width-5 wNAF, Jacobian tables          |  116_817_125 |  −8.1% |    9.78 MiB |  −8.3% |   413_335_328 | −6.5% |     24_593_089 |  +3.7% |
| Combined multiplication in verify      |   87_478_767 | −25.1% |    7.18 MiB | −26.6% |   412_601_208 | −0.2% |     24_599_742 |     0% |
| Iterative field inversion              |   86_057_048 |  −1.6% |    7.11 MiB |  −1.0% |   409_007_176 | −0.9% |     23_890_156 |  −2.9% |
| Verify without affine conversion       |   83_714_883 |  −2.7% |    6.93 MiB |  −2.5% |   409_007_176 |    0% |     23_890_156 |     0% |
| Precomputed tables for G (width 7)     |   72_794_211 | −13.0% |    5.98 MiB | −13.7% |   409_009_816 |    0% |     23_891_642 |     0% |

Columns:

- **ECDSA verify**: instructions for `verify (preparsed)`, sample 0, in
  `bench/ecdsa_verify.bench.mo`.
- **Verify heap**: memory allocated by the same call (temporary allocation,
  not retained memory).
- **BIP32 depth 5**: instructions for deriving a depth-5 path from an array
  path in `bench/bip32.bench.mo`.
- **`mul`, k < 2⁵⁷**: instructions for `mulPoint`, `k large`, in
  `bench/ec_arith.bench.mo`. Its scalars are below 2⁵⁷, so it doesn't show
  gains that only apply to full-size scalars, such as GLV.

For reference, [motoko_ecdsa](https://github.com/edjCase/motoko_ecdsa) 8.0.2
verifies a secp256k1 signature in 110_018_892 instructions with 5.41 MiB of
heap (its own benchmark, measured without `wasm-opt`).

## Steps

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
   bignum once at program start (in the Wasm start function, before
   `canister_init`), so they cost Wasm size and a one-time init cost.
   Measured on a canister that calls `Ecdsa.verify` (242_950 bytes after
   `wasm-opt -O3` without the tables), and with wasmtime fuel for the init
   cost:

   | Width | Points |        Wasm (-O3) | Init (once) | ECDSA verify | Δ vs no table |
   | ----: | -----: | ----------------: | ----------: | -----------: | ------------: |
   |     5 |     16 |   +5.4 KB (+2.2%) |    about 5k |   76_459_061 |         −8.7% |
   |     6 |     32 |  +10.8 KB (+4.4%) |   about 10k |   74_104_636 |        −11.5% |
   |     7 |     64 |  +21.4 KB (+8.8%) |   about 20k |   72_794_211 |        −13.0% |
   |     8 |    128 | +42.5 KB (+17.5%) |   about 39k |   71_661_465 |        −14.4% |

   Width 7 is the chosen trade-off. To change it, regenerate the module with
   another width; nothing else depends on it.

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
