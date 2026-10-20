// @testmode wasi

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Nat "mo:core/Nat";
import Runtime "mo:core/Runtime";

import Curves "../../src/ec/Curves";
import Fp "../../src/ec/Fp";
import Der "../../src/ecdsa/Der";
import Ecdsa "../../src/ecdsa/Ecdsa";
import Hex "../Hex";
import PublicKey "../../src/ecdsa/Publickey";
import TestUtils "../TestUtils";
import WycheproofEcdsaTestVectors "wycheproofEcdsaSecp256k1TestVectors";

type WycheproofEcdsaTestCase = WycheproofEcdsaTestVectors.WycheproofEcdsaTestCase;
let runTest = TestUtils.runTestWithDefaults;

func testWycheproofEcdsa(testCase : WycheproofEcdsaTestCase) {
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

  switch (
    PublicKey.decode(#sec1(key, Curves.secp256k1)),
    Der.decodeSignature(Blob.fromArray(sig)),
  ) {
    case (#ok(publicKey), #ok(signature)) {
      let actual = Ecdsa.verify(signature, publicKey, msg);
      let expected = testCase.result == "valid" or testCase.result == "acceptable";
      assert (expected == actual);
    };
    case _ {
      assert (testCase.result == "invalid");
    };
  };
};

runTest({
  title = "Wycheproof ECDSA";
  fn = testWycheproofEcdsa;
  vectors = WycheproofEcdsaTestVectors.testVectors;
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
