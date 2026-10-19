# AGENTS.md

`motoko-bitcoin` is a Motoko library of Bitcoin algorithms (addresses, scripts,
transactions, BIP32, ECDSA, and hashing), published to Mops as
[`bitcoin`](https://mops.one/bitcoin).

## Setup

- Motoko toolchain versions (`moc`, `pocket-ic`, `wasmtime`, `wasm-opt`) are
  pinned under `[toolchain]` in `mops.toml`. Don't assume system-installed
  versions. `[requirements] moc` is the minimum floor for users of the package.
- To install dependencies and the toolchain, run `mops install --locked`.

## Build, test, and format

- `mops test` runs the tests in `test/`.
- `mops bench` runs the benchmarks in `bench/`. The `[optimize]` section in
  `mops.toml` runs `wasm-opt` on them.
- To format, run
  `npx prettier --plugin prettier-plugin-motoko --write '**/*.{mo,json,md}'`
  after `npm install --no-save prettier prettier-plugin-motoko`. CI checks the
  same globs.

## Layout

- `src/` holds the library modules: encodings and hashes at the top level,
  `src/bitcoin/` for addresses, scripts, and transactions, `src/ec/` for
  elliptic-curve arithmetic, and `src/ecdsa/` for signatures.
- `test/` holds the tests (`*.test.mo`).
- `bench/` holds the benchmarks (`*.bench.mo`).

## Releasing

See [`RELEASING.md`](RELEASING.md) for how to release a version, how
publishing to Mops works, the secret and GitHub App it depends on, and how to
publish an existing tag again. In short, merging a PR that bumps `version` in
`mops.toml` with a matching `CHANGELOG.md` section tags, releases, and
publishes.

## Conventions

- Record user-facing changes in `CHANGELOG.md` (Keep a Changelog format).
- Prefer returning an option on invalid input over trapping. Version 0.2.1 made
  the decoders and address functions non-trapping (see `CHANGELOG.md`).
