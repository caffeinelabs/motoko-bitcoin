# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

### Changed

- Optimize `Ripemd160` (#20).

### Fixed

- `Ripemd160` and `Hmac` Digests now guard against accidentally writing more data after calling `sum()`.

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
