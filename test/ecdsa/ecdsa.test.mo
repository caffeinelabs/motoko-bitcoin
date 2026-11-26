// @testmode wasi

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Nat "mo:core/Nat";
import Nat8 "mo:core/Nat8";
import Runtime "mo:core/Runtime";

import Curves "../../src/ec/Curves";
import Fp "../../src/ec/Fp";
import Der "../../src/ecdsa/Der";
import Ecdsa "../../src/ecdsa/Ecdsa";
import Hex "../Hex";
import PublicKey "../../src/ecdsa/Publickey";
import TestUtils "../TestUtils";
import Secp256r1 "../ec/Secp256r1";
import WycheproofEcdsaTestVectors "wycheproofEcdsaSecp256k1TestVectors";
import WycheproofEcdsaSecp256r1TestVectors "wycheproofEcdsaSecp256r1TestVectors";

type WycheproofEcdsaTestCase = WycheproofEcdsaTestVectors.WycheproofEcdsaTestCase;
let runTest = TestUtils.runTestWithDefaults;

func testWycheproofEcdsa(curve : Curves.Curve, testCase : WycheproofEcdsaTestCase) {
  let (key, sig, msg) = switch (
    Hex.decode(testCase.key),
    Hex.decode(testCase.sig),
    Hex.decode(testCase.msg),
  ) {
    case (#ok(key), #ok(sig), #ok(msg)) { (key, sig, msg) };
    case _ {
      // Converting data from hex failed.
      Runtime.trap("Could not decode test data.");
    };
  };

  // Wycheproof flags integers without their leading zero byte as a legacy
  // encoding ("MissingZero"): "acceptable" in the older secp256k1 file,
  // "invalid" in the v1 files. The decoder rejects them (strict DER).
  let missingZero = testCase.flags.find(func(f : Text) : Bool = f == "MissingZero") != null;
  switch (
    PublicKey.decode(#sec1(key, curve)),
    Der.decodeSignature(Blob.fromArray(sig)),
  ) {
    case (#ok(publicKey), #ok(signature)) {
      assert not missingZero;
      let actual = Ecdsa.verify(signature, publicKey, msg);
      let expected = testCase.result == "valid" or testCase.result == "acceptable";
      assert (expected == actual);
    };
    case _ {
      assert (testCase.result == "invalid" or missingZero);
    };
  };
};

// DER-encodes a signature from the raw INTEGER contents of r and s.
func der(r : [Nat8], s : [Nat8]) : Blob {
  let header : [Nat8] = [0x30, (4 + r.size() + s.size()).toNat8(), 0x02, r.size().toNat8()];
  let middle : [Nat8] = [0x02, s.size().toNat8()];
  Blob.fromArray(header.concat(r).concat(middle).concat(s));
};

type DerCase = {
  title : Text;
  r : [Nat8];
  s : [Nat8];
  expected : ?{ r : Nat; s : Nat };
};

let ff32 : [Nat8] = Array.repeat<Nat8>(0xff, 32);
let max256 : Nat = 2 ** 256 - 1;

let derCases : [DerCase] = [
  { title = "minimal"; r = [0x01]; s = [0x7f]; expected = ?{ r = 1; s = 127 } },
  {
    title = "zero byte before high bit";
    r = [0x00, 0x80];
    s = [0x01];
    expected = ?{ r = 128; s = 1 };
  },
  {
    title = "33-byte r";
    r = [0x00 : Nat8].concat(ff32);
    s = [0x01];
    expected = ?{ r = max256; s = 1 };
  },
  {
    title = "33-byte s";
    r = [0x01];
    s = [0x00 : Nat8].concat(ff32);
    expected = ?{ r = 1; s = max256 };
  },
  { title = "negative r"; r = [0x80]; s = [0x01]; expected = null },
  { title = "negative s"; r = [0x01]; s = [0xff]; expected = null },
  { title = "r missing its zero byte"; r = ff32; s = [0x01]; expected = null },
  { title = "s missing its zero byte"; r = [0x01]; s = ff32; expected = null },
  {
    title = "r with excess zero";
    r = [0x00, 0x01];
    s = [0x01];
    expected = null;
  },
  {
    title = "s with excess zero";
    r = [0x01];
    s = [0x00, 0x7f];
    expected = null;
  },
  {
    title = "r with two leading zeros";
    r = [0x00, 0x00, 0x80];
    s = [0x01];
    expected = null;
  },
  {
    title = "33-byte r above 2^256";
    r = [0x01 : Nat8].concat(Array.repeat<Nat8>(0, 32));
    s = [0x01];
    expected = null;
  },
];

runTest({
  title = "DER decoding is strict";
  fn = func(c : DerCase) {
    let actual = switch (Der.decodeSignature(der(c.r, c.s))) {
      case (#ok(signature)) ?signature;
      case (#err(_)) null;
    };
    if (actual != c.expected) Runtime.trap(c.title # ": got " # debug_show actual);
  };
  vectors = derCases;
});

runTest({
  title = "DER encoding round-trips";
  fn = func(raw : [Nat8]) {
    let expectedR = raw.sliceToArray(0, 32).foldLeft(0, func(acc : Nat, b : Nat8) : Nat = acc * 256 + b.toNat());
    let expectedS = raw.sliceToArray(32, 64).foldLeft(0, func(acc : Nat, b : Nat8) : Nat = acc * 256 + b.toNat());
    switch (Der.decodeSignature(Der.encodeSignature(Blob.fromArray(raw)))) {
      case (#ok({ r; s })) assert (r == expectedR and s == expectedS);
      case (#err(e)) Runtime.trap(e);
    };
  };
  vectors = [
    ff32.concat(ff32),
    Array.tabulate<Nat8>(64, func(i) = if (i == 0 or i == 32) 0x00 else 0x7f),
    Array.tabulate<Nat8>(64, func(i) = if (i < 31 or (i >= 32 and i < 63)) 0x00 else 0x80),
  ];
});

runTest({
  title = "Wycheproof ECDSA";
  fn = func(testCase : WycheproofEcdsaTestCase) = testWycheproofEcdsa(Curves.secp256k1, testCase);
  vectors = WycheproofEcdsaTestVectors.testVectors;
});

runTest({
  title = "Wycheproof ECDSA secp256r1";
  fn = func(testCase : WycheproofEcdsaTestCase) = testWycheproofEcdsa(Secp256r1.curve, testCase);
  vectors = WycheproofEcdsaSecp256r1TestVectors.testVectors;
});

// Curves outside n < p < 2n, where verify can't use the projective check.
// The expected results come from a direct computation of x(R) mod n == r
// (Python), for every (r, s) and the public key Q = 3G.
type ToyCurveCase = {
  title : Text;
  p : Nat;
  n : Nat;
  a : Nat;
  b : Nat;
  g : (Nat, Nat);
  q : (Nat, Nat);
  valid : [(Nat, Nat)];
};

let toyCurveCases : [ToyCurveCase] = [
  {
    // n > p: the projective check would accept r >= p.
    title = "p = 5, n = 7";
    p = 5;
    n = 7;
    a = 2;
    b = 1;
    g = (0, 1);
    q = (3, 3);
    valid = [(1, 1), (1, 6), (3, 2), (3, 5)];
  },
  {
    // p > 2n: x(R) = r + 2n is a third candidate the projective check misses.
    title = "p = 13, n = 5";
    p = 13;
    n = 5;
    a = 2;
    b = 0;
    g = (1, 4);
    q = (12, 6);
    valid = [(1, 1), (1, 4), (2, 2), (2, 3)];
  },
];

runTest({
  title = "Verify on curves outside n < p < 2n";
  fn = func(c : ToyCurveCase) {
    let curve : Curves.Curve = {
      p = c.p;
      r = c.n;
      a = c.a;
      b = c.b;
      gx = c.g.0;
      gy = c.g.1;
      Fp = func(value : Nat) : Fp.Fp = Fp.Fp(value, c.p);
      glv = null;
    };
    let publicKey = {
      coords = { x = curve.Fp(c.q.0); y = curve.Fp(c.q.1) };
      curve;
    };
    let message = ("toy curve" : Blob).toArray();
    for (r in Nat.range(1, c.n)) {
      for (s in Nat.range(1, c.n)) {
        let expected = c.valid.find(func((vr, vs) : (Nat, Nat)) : Bool = vr == r and vs == s) != null;
        if (Ecdsa.verify({ r; s }, publicKey, message) != expected) {
          Runtime.trap(c.title # ": wrong result for (r, s) = " # debug_show (r, s));
        };
      };
    };
  };
  vectors = toyCurveCases;
});
