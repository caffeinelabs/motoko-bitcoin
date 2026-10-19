[![mops](https://oknww-riaaa-aaaam-qaf6a-cai.raw.ic0.app/badge/mops/bitcoin)](https://mops.one/bitcoin)
[![documentation](https://oknww-riaaa-aaaam-qaf6a-cai.raw.ic0.app/badge/documentation/bitcoin)](https://mops.one/bitcoin/docs)

# Algorithms for Bitcoin Integration in Motoko

Requires the [`mops`](https://docs.mops.one/quick-start) package manager for Motoko.

## Installation

```sh
mops add bitcoin
```

## Usage

Base58:

```motoko
import Base58 "mo:bitcoin/Base58";

let encoded : Text = Base58.encode([0x00, 0x01, 0x02]);
assert Base58.decodeOpt(encoded) == ?[0x00, 0x01, 0x02];

```

Base58Check:

```motoko
import Base58Check "mo:bitcoin/Base58Check";

let encoded : Text = Base58Check.encode([0x00, 0x01, 0x02]);
assert Base58Check.decode(encoded) == ?[0x00, 0x01, 0x02];

```

HMAC:

```motoko
import Hmac "mo:bitcoin/Hmac";

let key : [Nat8] = [0x01, 0x02, 0x03];

// HMAC-SHA256
let hmacSha256 : Hmac.Hmac = Hmac.sha256(key);
hmacSha256.writeArray([0x04, 0x05]);
var result : Blob = hmacSha256.sum();

// HMAC-SHA512
let hmacSha512 : Hmac.Hmac = Hmac.sha512(key);
hmacSha512.writeArray([0x04, 0x05]);
result := hmacSha512.sum();

// HMAC with a custom hash function
let hmacCustom : Hmac.Hmac = Hmac.new(
  key,
  {
    blockSize = 64;
    create = func() : Hmac.Digest {
      {
        writeArray = func(_data : [Nat8]) { /* process input */ };
        sum = func() : Blob = "" /* compute the hash */;
      };
    };
  },
);
hmacCustom.writeArray([0x04, 0x05]);
result := hmacCustom.sum();

```

An `Hmac` is one-shot: after `sum()`, further calls trap. Create a new one for
the next HMAC.

RIPEMD160:

```motoko
import Ripemd160 "mo:bitcoin/Ripemd160";

let digest = Ripemd160.Digest();
digest.write([0x01, 0x02]);
digest.write([0x03, 0x04]);
let result : [Nat8] = digest.sum();

// One-shot
assert Ripemd160.hash([0x01, 0x02, 0x03, 0x04]) == result;

```

EC:

```motoko
import Jacobi "mo:bitcoin/ec/Jacobi";
import Affine "mo:bitcoin/ec/Affine";
import Curves "mo:bitcoin/ec/Curves";

// Get secp256k1 curve parameters.
let secp256k1 : Curves.Curve = Curves.secp256k1;
let Fp = secp256k1.Fp;

// Create affine point on the secp256k1 curve
let basePointAffine : Affine.Point = #point(Fp(secp256k1.gx), Fp(secp256k1.gy), secp256k1);
// Convert to Jacobi point
let basePointJacobi : Jacobi.Point = Jacobi.fromAffine(basePointAffine);

// Scalar multiplication
let mul1 = Jacobi.mul(basePointJacobi, 1234);
let mul2 = Jacobi.mulBase(1234, Curves.secp256k1);

assert Jacobi.isEqual(mul1, mul2);

```

BIP32:

```motoko
import Bip32 "mo:bitcoin/Bip32";

let rootKey : ?Bip32.ExtendedPublicKey = Bip32.parse("xpub661MyMwAqRbcFtXgS5sYJABqqG9YLmC4Q1Rdap9gSE8NqtwybGhePY2gZ29ESFjqJoCu1Rupje8YtGqsefD265TMg7usUDFdp6W1EGMcet8", null);

// Derive a child key and serialize it as an xpub
let derived : ?Text = do ? {
  rootKey!.derivePath(#text "m/1/2/3")!.serialize();
};
assert derived != null;

```

Bech32:

```motoko
import Bech32 "mo:bitcoin/Bech32";

let encoded : Text = Bech32.encode("bc", [0x00, 0x01, 0x02], #BECH32);
let decoded = Bech32.decode("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4");

```

SegWit:

```motoko
import Segwit "mo:bitcoin/Segwit";

// A version-0 witness program of 20 bytes (P2WPKH)
let program : Segwit.WitnessProgram = {
  version = 0;
  program = [0x75, 0x1e, 0x76, 0xe8, 0x19, 0x91, 0x96, 0xd4, 0x54, 0x94, 0x1c, 0x45, 0xd1, 0xb3, 0xa3, 0x23, 0xf1, 0x43, 0x3b, 0xd6];
};
let address = Segwit.encode("bc", program);
let decoded = Segwit.decode("BC1QW508D6QEJXTDG4Y5R3ZARVARY0C5XW7KV8F3T4");

```

## Testing

Run all tests:

```sh
mops test
```

## Benchmarks

Benchmark files are under the `bench/` directory and cover encoding
(Base58/Base58Check/Bech32), hashing and HMAC, BIP32 derivation, EC arithmetic,
ECDSA verification, and Bitcoin transaction building and sighash. They use the
`bench-helper` mops package.

Run all benchmarks locally:

```sh
mops bench
```

Since 0.2.2 the benchmarks are compiled with moc 2.0.0 and optimized with the
`wasm-opt` post-pass (`[optimize]` in `mops.toml`). Their numbers are therefore
not comparable with those of earlier versions: the difference comes from the
measurement setup, not from a change in the code.

## Development

Format the code with:

```bash
npm install --no-save prettier prettier-plugin-motoko
npx prettier --plugin prettier-plugin-motoko --write '**/*.{mo,json,md}'
```

## Releasing

To release a new version:

1. Open a PR that bumps `version` in the `[package]` section of `mops.toml` and
   adds a matching `## [x.y.z]` section to `CHANGELOG.md`.
2. Merge the PR. The `Release tag` workflow tags the merge commit as `vx.y.z`
   and creates the GitHub release from the changelog section.
3. The tag push starts the `Publish on Mops` workflow, which publishes the
   package to [Mops](https://mops.one/bitcoin).

To publish an existing tag again, run `Publish on Mops` manually and pass the
tag.
