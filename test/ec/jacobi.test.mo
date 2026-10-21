import Array "mo:core/Array";
import Nat "mo:core/Nat";
import Runtime "mo:core/Runtime";
import VarArray "mo:core/VarArray";

import Common "../../src/Common";
import Curves "../../src/ec/Curves";
import Hex "../Hex";
import Jacobi "../../src/ec/Jacobi";
import Numbers "../../src/ec/Numbers";
import Secp256k1Generator "../../src/ec/Secp256k1Generator";
import Secp256k1TestVectors "Secp256k1TestVectors";
import TestUtils "../TestUtils";
import WycheproofEcdhTestVectors "wycheproofEcdhTestVectors";

type DoublingVector = Secp256k1TestVectors.DoublingVector;
type MultiplicationVector = Secp256k1TestVectors.MultiplicationVector;
type BaseMultiplicationVector = Secp256k1TestVectors.BaseMultiplicationVector;
type SerializationVector = Secp256k1TestVectors.SerializationVector;
type AdditionVector = Secp256k1TestVectors.AdditionVector;
type WycheproofEcdhTestCase = WycheproofEcdhTestVectors.WycheproofEcdhTestCase;

let runTest = TestUtils.runTestWithDefaults;

func getSecp256k1Point(coords : ?(Nat, Nat)) : Jacobi.Point {
  switch (coords) {
    case (?(x, y)) {
      Jacobi.fromNat(x, y, 1, Curves.secp256k1);
    };
    case (null) #infinity(Curves.secp256k1);
  };
};

func testAddition(vector : AdditionVector) {
  let inputPoint1 = getSecp256k1Point(vector.coords1);
  let inputPoint2 = getSecp256k1Point(vector.coords2);
  let expectedPoint = getSecp256k1Point(vector.output);
  let actual = Jacobi.add(inputPoint1, inputPoint2);
  assert (Jacobi.isEqual(expectedPoint, actual));
};

func testDoubling(vector : DoublingVector) {
  let inputPoint = getSecp256k1Point(vector.coords);
  let expectedPoint = getSecp256k1Point(vector.output);
  let actual = Jacobi.double(inputPoint);
  assert (Jacobi.isEqual(expectedPoint, actual));
};

func testMultiplication(vector : MultiplicationVector) {
  let inputPoint = getSecp256k1Point(vector.coords);
  let expectedPoint = getSecp256k1Point(vector.output);
  let actual = Jacobi.mul(inputPoint, vector.multiplicand);
  assert (Jacobi.isEqual(expectedPoint, actual));
};

func testBaseMultiplication(vector : BaseMultiplicationVector) {
  let expectedPoint = getSecp256k1Point(?vector.output);
  let actual = Jacobi.mulBase(vector.multiplicand, Curves.secp256k1);
  assert (Jacobi.isEqual(expectedPoint, actual));
};

func testSerializationUncompressed(vector : SerializationVector) {
  let inputPoint = getSecp256k1Point(vector.coords);
  let actual = Jacobi.toBytes(inputPoint, false);
  assert (vector.uncompressed == actual);
};

func testSerializationCompressed(vector : SerializationVector) {
  let inputPoint = getSecp256k1Point(vector.coords);
  let actual = Jacobi.toBytes(inputPoint, true);
  assert (vector.compressed == actual);
};

func testWycheproofEcdh(testCase : WycheproofEcdhTestCase) {
  var compressed : Bool = false;
  for (flag in testCase.flags.values()) {
    if (flag == "CompressedPoint") {
      compressed := true;
    };
  };

  switch (
    Hex.decode(testCase.publicKey),
    Hex.decode(testCase.privateKey),
    Hex.decode(testCase.output),
  ) {
    case (#ok(encodedPublicKey), #ok(privateKeyBytes), #ok(outputBytes)) {
      // Simple ASN parsing just by extracting the public key from it.
      let publicKeySize = if (compressed) 33 else 65;
      if (encodedPublicKey.size() < 23 + publicKeySize) {
        assert (testCase.result == "invalid");
        return;
      };
      let publicKey = Array.tabulate<Nat8>(
        publicKeySize,
        func(i) {
          encodedPublicKey[encodedPublicKey.size() - publicKeySize + i];
        },
      );

      // Align private key to 32 bytes because conversion to Nat function
      // expects a 32-byte array.
      let alignedPrivateKey = VarArray.repeat<Nat8>(0, 32);
      for (i in Nat.range(0, Nat.min(privateKeyBytes.size(), 32))) {
        alignedPrivateKey[alignedPrivateKey.size() - 1 - i] := privateKeyBytes[privateKeyBytes.size() - 1 - i];
      };
      let privateKey : Nat = Common.readBE256(alignedPrivateKey.toArray(), 0);

      // Read expected output. It is sometimes empty.
      let expectedOutput : ?Nat = if (outputBytes.size() > 0) {
        ?(Common.readBE256(outputBytes, 0));
      } else {
        null;
      };

      switch (Jacobi.fromBytes(publicKey, Curves.secp256k1), expectedOutput) {
        case (?(#point(point)), ?(expectedOutput)) {
          // Point is successfully decoded, compute ECDH.
          switch (
            Jacobi.toAffine(
              Jacobi.mul(#point point, privateKey)
            )
          ) {
            case (#point(x, _y, _)) {
              // If we are here, then the test is expected to succeed.
              assert (testCase.result != "invalid");
              assert (expectedOutput == x.value);
            };
            case _ {
              Runtime.trap("Test failed.");
            };
          };
        };
        case _ {
          // Point decoding is allowed to fail if the test case is not valid.
          if (testCase.result != "invalid") {
            Runtime.trap("Could not decode point.");
          };
        };
      };
    };
    case _ {
      // Converting data from hex failed.
      Runtime.trap("Could not decode test data.");
    };
  };
};

// Jacobi Points over Secp256k1 Curve

runTest({
  title = "Addition";
  fn = testAddition;
  vectors = Secp256k1TestVectors.additionVectors;
});

runTest({
  title = "Doubling";
  fn = testDoubling;
  vectors = Secp256k1TestVectors.doublingVectors;
});

runTest({
  title = "Multiplication";
  fn = testMultiplication;
  vectors = Secp256k1TestVectors.multiplicationVectors;
});

runTest({
  title = "Base Multiplication";
  fn = testBaseMultiplication;
  vectors = Secp256k1TestVectors.baseMultiplicationVectors;
});

runTest({
  title = "Compressed Serialization";
  fn = testSerializationCompressed;
  vectors = Secp256k1TestVectors.serializationVectors;
});

runTest({
  title = "Uncompressed Serialization";
  fn = testSerializationUncompressed;
  vectors = Secp256k1TestVectors.serializationVectors;
});

runTest({
  title = "Wycheproof ECDH";
  fn = testWycheproofEcdh;
  vectors = WycheproofEcdhTestVectors.testVectors;
});

type MulAddVector = {
  point1 : Jacobi.Point;
  a : Nat;
  point2 : Jacobi.Point;
  b : Nat;
};

func testMulAdd({ point1; a; point2; b } : MulAddVector) {
  let expected = Jacobi.add(Jacobi.mul(point1, a), Jacobi.mul(point2, b));
  let actual = Jacobi.mulAdd(point1, a, point2, b);
  assert (Jacobi.isEqual(expected, actual));
};

let mulAddVectors : [MulAddVector] = do {
  let curve = Curves.secp256k1;
  let r = curve.r;
  let g = Jacobi.base(curve);
  let q = Jacobi.mul(g, 0xc6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5);
  let inf : Jacobi.Point = #infinity(curve);
  let k1 = 0x4b688df40bcedbe641ddb16ff0a1842d9c67ea1c3bf63f3e0471baa664531d1a;
  let k2 = 0xe4437ed6010e88286f547fa90abfe4c3e4437ed6010e88286f547fa90abfe4c3;
  [
    { point1 = g; a = k1; point2 = q; b = k2 },
    { point1 = g; a = r - 1; point2 = q; b = r - 1 },
    { point1 = g; a = 1; point2 = q; b = 1 },
    { point1 = g; a = 0; point2 = q; b = k2 },
    { point1 = g; a = k1; point2 = q; b = 0 },
    { point1 = g; a = 0; point2 = q; b = 0 },
    { point1 = inf; a = k1; point2 = q; b = k2 },
    { point1 = g; a = k1; point2 = inf; b = k2 },
    // Same point: the sum needs a doubling inside the shared loop.
    { point1 = g; a = k1; point2 = g; b = k1 },
    { point1 = g; a = k1; point2 = g; b = k2 },
    // Cancels to the point at infinity.
    { point1 = g; a = k1; point2 = g; b = r - k1 },
    { point1 = g; a = k1; point2 = Jacobi.neg(g); b = k1 },
    // Scalars of r and above.
    { point1 = g; a = k1 + r; point2 = q; b = r },
  ];
};

runTest({
  title = "Combined multiplication a * P1 + b * P2";
  fn = testMulAdd;
  vectors = mulAddVectors;
});

// Double-and-add with Jacobi.double and Jacobi.add only, independent of
// the GLV and table code in Jacobi.mul.
func doubleAndAdd(point : Jacobi.Point, k : Nat) : Jacobi.Point {
  var acc : Jacobi.Point = #infinity(Curves.secp256k1);
  for (bit in Numbers.toBinary(k).values()) {
    acc := Jacobi.double(acc);
    if (bit) acc := Jacobi.add(acc, point);
  };
  acc;
};

do {
  let curve = Curves.secp256k1;
  let ?glv = curve.glv else Runtime.trap("secp256k1 has GLV parameters");
  let g = Jacobi.base(curve);
  let twoG = Jacobi.double(g);
  // phi(G) = (beta * x, y) must equal lambda * G.
  let (phiX, phiY, _) = Secp256k1Generator.phiMultiples[0];
  assert (Jacobi.isEqual(Jacobi.fromNat(phiX, phiY, 1, curve), doubleAndAdd(g, glv.lambda)));

  var expected = g;
  for (i in Nat.range(0, Secp256k1Generator.multiples.size())) {
    let (x, y, z) = Secp256k1Generator.multiples[i];
    let (px, py, pz) = Secp256k1Generator.phiMultiples[i];
    assert (z == 1 and pz == 1);
    // (2i + 1) * G, built as G + 2G + ... + 2G.
    assert (Jacobi.isEqual(Jacobi.fromNat(x, y, 1, curve), expected));
    assert (px == glv.beta * x % curve.p and py == y);
    expected := Jacobi.add(expected, twoG);
  };

  // H = 2^shift * G by repeated doubling, and phi(H) = lambda * H.
  var h = g;
  for (_ in Nat.range(0, Secp256k1Generator.shift)) h := Jacobi.double(h);
  let twoH = Jacobi.double(h);
  let (phiHX, phiHY, _) = Secp256k1Generator.phiShiftedMultiples[0];
  assert (Jacobi.isEqual(Jacobi.fromNat(phiHX, phiHY, 1, curve), doubleAndAdd(g, glv.lambda * 2 ** Secp256k1Generator.shift % curve.r)));

  var expectedH = h;
  for (i in Nat.range(0, Secp256k1Generator.shiftedMultiples.size())) {
    let (x, y, z) = Secp256k1Generator.shiftedMultiples[i];
    let (px, py, pz) = Secp256k1Generator.phiShiftedMultiples[i];
    assert (z == 1 and pz == 1);
    assert (Jacobi.isEqual(Jacobi.fromNat(x, y, 1, curve), expectedH));
    assert (px == glv.beta * x % curve.p and py == y);
    expectedH := Jacobi.add(expectedH, twoH);
  };
};
