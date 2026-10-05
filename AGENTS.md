# AGENTS.md

A Motoko library of algorithms for Bitcoin integration (Base58, Bech32/Segwit, BIP32, EC, ECDSA, hashing).

## Prerequisites

This project uses the [`mops`](https://docs.mops.one/quick-start) package manager for Motoko. Install dependencies with:

```sh
mops install
```

Pinned toolchain versions are declared in `mops.toml` (`[toolchain]`): `moc = 1.11.0`, `pocket-ic = 14.0.0`, `wasmtime = 44.0.3`. The minimum `moc` is `1.4.0`.

## Build, test, format

- Run tests: `mops test` (CI uses this; the README documents `mops test --mode wasi`).
- Run benchmarks: `mops bench`.
- Format check: Motoko files are formatted with Prettier plus `prettier-plugin-motoko`. CI runs:

```sh
npx prettier --check --plugin=prettier-plugin-motoko **/*.mo
```

  Formatting options are configured in `.prettierrc` (2-space indent, `printWidth` 80, semicolons, trailing ES5 commas). CI's format job fails if any `.mo` file is not formatted.

## Layout

- `src/` — library source. Subdirectories `ec/` (elliptic-curve arithmetic) and `ecdsa/` group related modules; `bitcoin/` holds transaction logic.
- `test/` — tests, named `*.test.mo`. `TestUtils.mo` and `Hex.mo` are shared helpers.
- `bench/` — performance benchmarks, named `*.bench.mo`.

## Conventions

- `package.json` and `package-lock.json` are git-ignored; the format job generates `package.json` by installing `prettier` and `prettier-plugin-motoko` on the fly. Do not commit them.
- `mops.lock`, `.mops/`, and build output (`test/_out/`, `build/`, `.dfx/`) are git-ignored and must not be hand-edited or committed.
