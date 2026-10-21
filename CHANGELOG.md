# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Add `Numbers.toWnaf()`, which computes width-`w` NAF digits.
- Add `Jacobi.mulAdd()`, which computes `a * P1 + b * P2` faster than two
  separate multiplications.
- Add `Secp256k1Generator`, the precomputed multiples of the secp256k1
  generator used by `Jacobi`. It is internal to the package and not a stable
  API.

### Changed

- Speed up `Jacobi` point arithmetic on secp256k1. See
  [`bench/OPTIMIZATIONS.md`](https://github.com/caffeinelabs/motoko-bitcoin/blob/main/bench/OPTIMIZATIONS.md)
  for what each step delivered.
  - A modular reduction specialized to the secp256k1 prime (verify −12.9%).
  - Field arithmetic on canonical `Nat` residues instead of signed `Int`
    values (verify −8.0%, verify heap −9.4%).
  - Width-5 wNAF digits with tables of odd multiples in the GLV
    multiplication (verify −8.1%, verify heap −8.3%).
  - ECDSA verification computes `u1 * G + u2 * Q` with one combined
    multiplication (verify −25.1%, verify heap −26.6%).
  - `Field.inverse()` uses an iterative extended Euclidean algorithm with one
    division per step (one inversion −22%, verify −1.6%).
  - ECDSA verification compares the result in Jacobian coordinates and no
    longer converts it to affine coordinates, on curves whose order n and
    field prime p satisfy n < p < 2n, such as secp256k1 (verify −2.7%).
    Other curves keep the affine check.
  - Precomputed tables of the secp256k1 generator for the `G` half of
    verification (verify −13.0%, verify heap −13.7%; Wasm +21 KB).
  - `Field.mul()` reduces modulo the secp256k1 prime without a bignum
    division, and `Fp.sqrt()` uses an addition chain on secp256k1 (public key
    decompression −72%, BIP32 derivation −21.6%).
  - `Jacobi.mul()` and `Jacobi.mulBase()` use the precomputed generator
    tables (`mulBase` −19.8%, BIP32 derivation −17.4%).
  - A cheaper point doubling for curves with a = 0 (verify −5.7%, BIP32
    derivation −7.7%, `mulBase` −9.2%).
  - Multiples of the secp256k1 generator split each GLV half once more, at
    2⁶⁴, against precomputed tables for `2^64 * G` (`mulBase` −29.7%, BIP32
    derivation −24.7%). The generator tables now use width 6, so the Wasm
    size stays the same.
  - `Numbers.toWnaf()` recodes on 64-bit machine words instead of bignums,
    42 times faster (verify −11.4%, BIP32 derivation −7.7%).
  - Point additions with fewer field additions and subtractions (verify
    −2.3%, BIP32 derivation −2.1%).

## [0.2.3] - 2026-10-19

### Added

- Add the `Curves.Glv` type with the GLV endomorphism parameters of secp256k1.

### Changed

- Speed up `Jacobi.mul()` and `Jacobi.mulBase()` on secp256k1 with the GLV
  endomorphism: about 34% fewer instructions for 256-bit scalars. ECDSA
  verification and BIP32 derivation are 29–35% cheaper.
- **Breaking:** `Curves.Curve` has a new field `glv : ?Glv`. Code that
  constructs its own `Curve` values must add it (`glv = null` keeps the
  previous scalar multiplication).

## [0.2.2] - 2026-10-16

### Changed

- Update `core` from `2.6.0` to `2.6.2`.
- Update `sha2` from `0.1.14` to `0.3.0`.
- Update README.

## [0.2.1] - 2026-07-12

### Added

- Add `isBase58Alphabet()` and `decodeOpt()` to `Base58.mo`.
- Make the `EcdsaProxy` type in `bitcoin/Bitcoin.mo` public.

### Changed

- Update `core` from `2.5.0` to `2.6.0`.
- Optimize `Ripemd160` ([#20](https://github.com/caffeinelabs/motoko-bitcoin/pull/20)).
- **Breaking:** `Jacobi.fromNat()` now returns `Point` instead of `?Point`.

### Fixed

- **Breaking:** `Ripemd160` and `Hmac` Digests now assert that no more data is written after calling `sum()`.
- Make `Bech32.decode()` accept all-numeric input.
- Avoid trap in `Base58Check.decode()` on short input.
- Check for invalid input in `Wif.decode()` and `Segwit.encode()`.
- Make non-trapping: `Address.addressFromText()`, `Address.scriptPubKey()`, `P2pkh.decodeAddress()`, `P2pkh.makeScript()`, `Bitcoin.buildTransaction()`, `Wif.decode()`.

## [0.2.0] - 2026-04-22

### Changed

- Optimize (de)serializations in `Bech32`, `Base58`, `Segwit`.
- **Breaking:** Add length assertions inside `Bech32.encode()`.
- Migrate code from `base` to `core`.

### Removed

- **Breaking:** Remove redundant `toBytes` function in `bitcoin/TxOutput.mo` (use class method instead).

### Fixed

- Taproot sighash now uses actual transaction values instead of hardcoded `locktime=0` and `version=2` ([#14](https://github.com/dfinity/motoko-bitcoin/issues/14)).
- **Breaking:** Lowercase character range in `Bech32.mo` was incorrect ([#13](https://github.com/dfinity/motoko-bitcoin/issues/13)).
- **Breaking:** Reject BIP32 paths with double-slashes in `Bip32.mo`.

## [0.1.1]

### Added

- Add `CODEOWNERS`.

### Changed

- Update dependencies: `base`.

### Fixed

- Fix tests and formatting.
