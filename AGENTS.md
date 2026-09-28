# AGENTS.md

Motoko library implementing algorithms for Bitcoin integration (Base58, Bech32/Segwit, BIP32, EC/secp256k1, ECDSA, hashing/HMAC, transaction building).

## Prerequisites

Uses the [`mops`](https://docs.mops.one/quick-start) package manager for Motoko. Install dependencies before building or testing:

```
mops install
```

## Test

```
mops test
```

The README also documents running with `mops test --mode wasi`.

## Format

Formatting is enforced in CI with Prettier and the Motoko plugin. Check with:

```
npx prettier --check --plugin=prettier-plugin-motoko **/*.mo
```

Formatting config lives in `.prettierrc` (2-space indent, `printWidth` 80, semicolons). CI fails if any `*.mo` file is not formatted.

## Benchmarks

```
mops bench
```

## Layout

- `src/` — library source; submodules `bitcoin/`, `ec/`, and `ecdsa/`.
- `test/` — tests (`*.test.mo`) plus helpers `Hex.mo` and `TestUtils.mo`.
- `bench/` — performance benchmarks (`*.bench.mo`).

## Conventions

- Pinned toolchain versions are declared in `mops.toml` under `[toolchain]` (e.g. `moc`, `pocket-ic`, `wasmtime`); do not assume other versions.
- Record user-facing changes in `CHANGELOG.md` (Keep a Changelog format, Semantic Versioning). Mark API-breaking changes as **Breaking**.
- `package.json`, `node_modules/`, `mops.lock`, `.mops/`, and build output are git-ignored and generated; do not commit or hand-edit them.
