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

## Tried and not adopted

- **Affine wNAF tables** (after step 3). Converting each table to affine
  coordinates with one batched inversion (Montgomery's trick) lets the main
  loop use mixed additions again. But one inversion via the extended
  Euclidean algorithm costs about 3.7M instructions, as much as the mixed
  additions save: verify measured 117_561_742 (+0.6%), BIP32 depth 5
  412_244_576 (−0.3%), and `mul` with a short scalar got 38% slower. Worth
  retrying with a faster inversion.
