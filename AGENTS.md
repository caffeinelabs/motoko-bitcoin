# AGENTS.md

Motoko library of algorithms for Bitcoin integration, distributed as the `bitcoin` package.

## Prerequisites

This project uses the [`mops`](https://docs.mops.one/quick-start) package manager for Motoko. Install dependencies before building or testing:

```sh
mops install
```

The pinned toolchain (see `mops.toml`) is `moc` 1.11.0, `pocket-ic` 14.0.0, and `wasmtime` 44.0.3.

## Test

```sh
mops test
```

Tests can also be run against the WASI backend (as documented in `README.md`):

```sh
mops test --mode wasi
```

## Benchmarks

```sh
mops bench
```

## Format

Formatting is enforced in CI with Prettier and the `prettier-plugin-motoko` plugin over all `.mo` files. Check locally with:

```sh
npx prettier --check --plugin=prettier-plugin-motoko **/*.mo
```

Prettier config (`.prettierrc`) pins `printWidth` 80, `tabWidth` 2, spaces (no tabs), semicolons, and `es5` trailing commas.

## Layout

- `src/` — library source (`.mo` modules), with subpackages `src/bitcoin`, `src/ec`, `src/ecdsa`.
- `test/` — test suites (`*.test.mo`), with shared helpers `test/Hex.mo` and `test/TestUtils.mo`.
- `bench/` — performance benchmark suites (`*.bench.mo`).

## Conventions

- Source and test files are written in Motoko; import modules by path, e.g. `import Base58 "src/Base58";`.
- CI runs two separate jobs that must both pass: `mops test` and the Prettier format check above.
