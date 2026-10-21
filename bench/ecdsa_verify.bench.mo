import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";
import VarArray "mo:core/VarArray";

import Bench "mo:bench-helper";

import Curves "../src/ec/Curves";
import Der "../src/ecdsa/Der";
import Ecdsa "../src/ecdsa/Ecdsa";
import PublicKey "../src/ecdsa/Publickey";
import Secp256r1 "../test/ec/Secp256r1";
import TestVectors "../test/ecdsa/wycheproofEcdsaSecp256k1TestVectors";
import TestVectorsR1 "../test/ecdsa/wycheproofEcdsaSecp256r1TestVectors";

module {

  // Minimal hex decoder (lowercase/uppercase supported)
  func toNibble(c : Nat8) : Nat8 {
    if (c >= 0x30 and c <= 0x39) { return c - 0x30 };
    let cl = if (c >= 0x41 and c <= 0x5a) c + 32 else c; // upper->lower
    if (cl >= 0x61 and cl <= 0x66) { return cl - 0x61 + 10 };
    0;
  };
  public func decode(t : Text) : [Nat8] {
    let b = Blob.toArray(Text.encodeUtf8(t));
    let n = b.size();
    if (n == 0) return [];
    let out = VarArray.repeat<Nat8>(0, (n + 1) / 2);
    var oi = 0;
    var i = 0;
    if (n % 2 == 1) {
      out[oi] := toNibble(b[i]);
      oi += 1;
      i += 1;
    };
    while (i + 1 < n) {
      let hi = toNibble(b[i]);
      let lo = toNibble(b[i + 1]);
      out[oi] := (hi << 4) + lo;
      oi += 1;
      i += 2;
    };
    out.toArray();
  };

  public func init() : Bench.V1 {
    let schema : Bench.Schema = {
      name = "ECDSA verify: DER vs raw (DER decode cost)";
      description = "Compare verifying using DER decode per run vs reusing parsed signature";
      rows = ["DER+verify", "verify (preparsed)"];
      cols = ["sample 0", "sample 1", "secp256r1"];
    };

    // Valid signatures; the secp256r1 one exercises the generic code paths.
    let samples = [TestVectors.testVectors[0], TestVectors.testVectors[2], TestVectorsR1.testVectors[2]];
    let curves = [Curves.secp256k1, Curves.secp256k1, Secp256r1.curve];

    // Pre-parse signatures and keys
    let parsed = Array.tabulate<(Ecdsa.PublicKey, Ecdsa.Signature)>(
      samples.size(),
      func i {
        let s = samples[i];
        let keyBytes = decode(s.key);
        let sigBytes = decode(s.sig);
        let pk = switch (PublicKey.decode(#sec1(keyBytes, curves[i]))) {
          case (#ok v) v;
          case (_) Runtime.trap("Invalid ECDSA benchmark public key fixture");
        };
        let sig = switch (Der.decodeSignature(Blob.fromArray(sigBytes))) {
          case (#ok v) v;
          case (_) Runtime.trap("Invalid ECDSA benchmark signature fixture");
        };
        (pk, sig);
      },
    );

    func run(ri : Nat, ci : Nat) {
      let s = samples[ci];
      let msgBytes = decode(s.msg);
      switch (ri) {
        case (0) {
          let keyBytes = decode(s.key);
          let sigBytes = decode(s.sig);
          switch (PublicKey.decode(#sec1(keyBytes, curves[ci])), Der.decodeSignature(Blob.fromArray(sigBytes))) {
            case (#ok pk, #ok sig) { ignore Ecdsa.verify(sig, pk, msgBytes) };
            case (_) {};
          };
        };
        case (1) {
          let (pk, sig) = parsed[ci];
          ignore Ecdsa.verify(sig, pk, msgBytes);
        };
        case (_) {};
      };
    };

    Bench.V1(schema, run);
  };
};
