/// Jacobian-coordinate elliptic curve operations.
///
/// Intended for public-data operations only; not constant-time for secret
/// inputs.
///
/// ```motoko name=import
/// import Jacobi "mo:bitcoin/ec/Jacobi";
/// ```

// EC operations using Jacobian coordinates.
//
// This implementation is intended for use within Internet Computer canisters
// which must only execute public operations. The code does not account for
// side-channels as they're not relevant to the use case.
//
// Therefore, DO NOT use this code for any operations involving secrets.

import Int "mo:core/Int";
import Nat "mo:core/Nat";
import Runtime "mo:core/Runtime";

import Affine "Affine";
import Curves "Curves";
import BaseFp "Fp";
import Numbers "Numbers";

module {
  type Fp = BaseFp.Fp;

  // Internal Jacobian coordinates: canonical residues in [0, p). A point
  // with Y = 0 or Z = 0 is the point at infinity.
  type Coords = (Nat, Nat, Nat);

  let SECP256K1_P : Nat = 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f;
  // 2^256 - p = 2^32 + 977
  let SECP256K1_C : Nat = 0x1000003d1;

  // Reduces a product of two residues (so t < p^2) modulo `p`. For the
  // secp256k1 prime it folds the bits above 2^256 back in using
  // 2^256 = 2^32 + 977 (mod p) instead of a bignum division: two folds bring
  // t < 2^512 below 2^256 + 2^67 < 2p.
  func reduce(t : Nat, p : Nat) : Nat {
    if (p != SECP256K1_P) return t % p;
    let tHi = Nat.bitshiftRight(t, 256);
    let tLo : Nat = t - Nat.bitshiftLeft(tHi, 256);
    let u = tLo + tHi * SECP256K1_C;
    let uHi = Nat.bitshiftRight(u, 256);
    let uLo : Nat = u - Nat.bitshiftLeft(uHi, 256);
    let v = uLo + uHi * SECP256K1_C;
    if (v >= p) v - p else v;
  };

  func fmul(a : Nat, b : Nat, p : Nat) : Nat = reduce(a * b, p);
  func fsqr(a : Nat, p : Nat) : Nat = reduce(a * a, p);
  func fadd(a : Nat, b : Nat, p : Nat) : Nat {
    let s = a + b;
    if (s >= p) s - p else s;
  };
  func fsub(a : Nat, b : Nat, p : Nat) : Nat = if (a >= b) a - b else a + p - b;
  func fdbl(a : Nat, p : Nat) : Nat = fadd(a, a, p);

  /// Jacobian point representation.
  public type Point = {
    #infinity : Curves.Curve;
    #point : (Fp, Fp, Fp, Curves.Curve);
  };

  /// Decodes SEC1 bytes into a Jacobian point on `curve`.
  // Deserialize given data into a point on the given curve. This supports
  // compressed and uncompressed SEC-1 formats.
  // Returns null if data is not in correct format, data size is not exactly
  // equal to the serialized point size, or if deserialized point is not on the
  // given curve.
  public func fromBytes(data : [Nat8], curve : Curves.Curve) : ?Point {
    switch (Affine.fromBytes(data, curve)) {
      case (null) null;
      case (?(#infinity(curve))) ?(#infinity(curve));
      case (?#point(x, y, curve)) ?#point(x, y, curve.Fp(1), curve);
    };
  };

  /// Encodes a Jacobian point into SEC1 bytes.
  public func toBytes(point : Point, compressed : Bool) : [Nat8] {
    Affine.toBytes(toAffine(point), compressed);
  };

  /// Checks whether a Jacobian point lies on its curve.
  public func isOnCurve(point : Point) : Bool {
    Affine.isOnCurve(toAffine(point));
  };

  /// Converts an affine point to Jacobian coordinates.
  public func fromAffine(point : Affine.Point) : Point {
    switch point {
      case (#infinity(curve)) #infinity(curve);
      case (#point(x, y, curve)) #point(x, y, curve.Fp(1), curve);
    };
  };

  /// Creates a Jacobian point from raw coordinates.
  public func fromNat(x : Nat, y : Nat, z : Nat, curve : Curves.Curve) : Point {
    #point(curve.Fp(x), curve.Fp(y), curve.Fp(z), curve);
  };

  /// Returns the generator point for `curve`.
  public func base(curve : Curves.Curve) : Point {
    #point(curve.Fp(curve.gx), curve.Fp(curve.gy), curve.Fp(1), curve);
  };

  /// Compares two Jacobian points for equality.
  public func isEqual(point1 : Point, point2 : Point) : Bool {
    switch (normalizeInfinity(point1), normalizeInfinity(point2)) {
      case (#infinity(curve1), #infinity(curve2)) {
        Curves.isEqual(curve1, curve2);
      };
      case (#point(x1, y1, z1, curve1), #point(x2, y2, z2, curve2)) {
        if (not Curves.isEqual(curve1, curve2)) {
          false;
        } else {
          let zz1 = z1.sqr();
          let zz2 = z2.sqr();

          (x1.mul(zz2).isEqual(x2.mul(zz1))) and (y1.mul(zz2).mul(z2).isEqual(y2.mul(zz1.mul(z1))));
        };
      };
      case (_) false;
    };
  };

  /// Returns true if `point` is at infinity.
  public func isInfinity(point : Point) : Bool {
    switch point {
      case (#infinity(_)) true;
      case (#point(_, _, z, curve)) z.isEqual(curve.Fp(0));
    };
  };

  /// Converts a Jacobian point to affine coordinates.
  public func toAffine(point : Point) : Affine.Point {
    let scaledPoint = scale(point);
    switch scaledPoint {
      case (#infinity(curve)) #infinity(curve);
      case (#point(x, y, _, curve)) #point(x, y, curve);
    };
  };

  /// Negates a point.
  public func neg(point : Point) : Point {
    switch (normalizeInfinity(point)) {
      case (#infinity(curve)) #infinity(curve);
      case (#point(x, y, z, curve)) #point(x, y.neg(), z, curve);
    };
  };

  /// Normalizes a Jacobian point so that `z = 1`.
  public func scale(point : Point) : Point {
    switch (normalizeInfinity(point)) {
      case (#infinity(curve)) #infinity(curve);
      case (#point(x, y, z, curve)) {
        if (z.isEqual(curve.Fp(1))) {
          return point;
        };

        let zInverse = z.inverse();
        let zzInverse = zInverse.sqr();

        let newX = x.mul(zzInverse);
        let newY = y.mul(zzInverse).mul(zInverse);
        let newZ = curve.Fp(1);

        #point(newX, newY, newZ, curve);
      };
    };
  };

  /// Returns point doubling result.
  public func double(point : Point) : Point {
    switch (normalizeInfinity(point)) {
      case (#infinity(curve)) #infinity(curve);
      case (#point(x, y, z, curve)) {
        let (x2, y2, z2) = doDouble(x.value, y.value, z.value, curve.a, curve.p);
        #point(curve.Fp(x2), curve.Fp(y2), curve.Fp(z2), curve);
      };
    };
  };

  /// Multiplies a point by scalar `other`.
  public func mul(point : Point, other : Nat) : Point {
    if (other == 0) {
      return #infinity(getCurve(point));
    };
    switch (scale(point)) {
      case (#infinity(curve)) #infinity(curve);
      case (#point(x2, y2, _, curve)) {
        switch (curve.glv) {
          case (?glv) return mulGlv(x2, y2, other, glv, curve);
          case null {};
        };
        var p : Coords = (0, 0, 1);
        let naf = Numbers.toNaf(other);
        let y2neg = y2.neg().value;

        for (i in Nat.rangeByInclusive(naf.size() - 1, 0, -1)) {
          let nafItem : Int = naf[i];
          p := doDouble(p.0, p.1, p.2, curve.a, curve.p);
          if (nafItem < 0) {
            p := _add(
              p.0,
              p.1,
              p.2,
              x2.value,
              y2neg,
              1,
              curve.a,
              curve.p,
            );
          } else if (nafItem > 0) {
            p := _add(p.0, p.1, p.2, x2.value, y2.value, 1, curve.a, curve.p);
          };
        };
        if (p.1 == 0 or p.2 == 0) {
          return #infinity(curve);
        };
        #point(curve.Fp(p.0), curve.Fp(p.1), curve.Fp(p.2), curve);
      };
    };
  };

  /// Scalar multiplication using the GLV endomorphism. Decomposes the scalar
  /// `k mod r` into `(k1, k2)` such that `k1 + lambda * k2 == k (mod r)` and
  /// both halves are roughly half the bit-length of `r`. Then computes
  /// `k1 * P + k2 * phi(P)` with a Straus/Shamir-style interleaved-NAF loop,
  /// where `phi(X, Y, Z) = (beta * X, Y, Z)` in Jacobian coordinates.
  /// Caller guarantees `(x, y)` is the affine representation (Z=1) of P and
  /// that `scalar != 0`.
  func mulGlv(
    x : Fp,
    y : Fp,
    scalar : Nat,
    glv : Curves.Glv,
    curve : Curves.Curve,
  ) : Point {
    let n : Int = curve.r;
    let k : Int = scalar % curve.r;
    if (k == 0) {
      return #infinity(curve);
    };
    let halfN : Int = n / 2;

    // Both `b2` and `-b1` are positive for valid GLV bases, so the numerators
    // are non-negative and Motoko's truncating Int division yields rounding
    // to nearest (with halves rounded away from zero, which is acceptable).
    let c1 : Int = (glv.b2 * k + halfN) / n;
    let c2 : Int = (-glv.b1 * k + halfN) / n;
    let k1 : Int = k - c1 * glv.a1 - c2 * glv.a2;
    let k2 : Int = -c1 * glv.b1 - c2 * glv.b2;

    let absK1 = Int.abs(k1);
    let absK2 = Int.abs(k2);

    let p1x = x.value;
    let yPos = y.value;
    let yNeg = y.neg().value;
    let p1y = if (k1 < 0) yNeg else yPos;
    let p1yAlt = if (k1 < 0) yPos else yNeg;
    let p2x = x.mul(curve.Fp(glv.beta)).value;
    let p2y = if (k2 < 0) yNeg else yPos;
    let p2yAlt = if (k2 < 0) yPos else yNeg;

    let naf1 = Numbers.toNaf(absK1);
    let naf2 = Numbers.toNaf(absK2);
    let len = if (naf1.size() > naf2.size()) naf1.size() else naf2.size();

    var p : Coords = (0, 0, 1);
    for (i in Nat.rangeByInclusive(len - 1, 0, -1)) {
      p := doDouble(p.0, p.1, p.2, curve.a, curve.p);
      if (i < naf1.size()) {
        let d : Int = naf1[i];
        if (d > 0) {
          p := _add(p.0, p.1, p.2, p1x, p1y, 1, curve.a, curve.p);
        } else if (d < 0) {
          p := _add(p.0, p.1, p.2, p1x, p1yAlt, 1, curve.a, curve.p);
        };
      };
      if (i < naf2.size()) {
        let d : Int = naf2[i];
        if (d > 0) {
          p := _add(p.0, p.1, p.2, p2x, p2y, 1, curve.a, curve.p);
        } else if (d < 0) {
          p := _add(p.0, p.1, p.2, p2x, p2yAlt, 1, curve.a, curve.p);
        };
      };
    };
    if (p.1 == 0 or p.2 == 0) {
      return #infinity(curve);
    };
    #point(curve.Fp(p.0), curve.Fp(p.1), curve.Fp(p.2), curve);
  };

  /// Multiplies the curve generator by scalar `other`.
  public func mulBase(other : Nat, curve : Curves.Curve) : Point {
    mul(base(curve), other);
  };

  /// Adds two Jacobian points.
  ///
  /// Traps with `"Cannot add two points on different curves"` when
  /// `point1` and `point2` belong to different curves. Otherwise never
  /// traps; identity, doubling, and infinity cases are handled.
  public func add(point1 : Point, point2 : Point) : Point {
    if (not Curves.isEqual(getCurve(point1), getCurve(point2))) {
      Runtime.trap("Cannot add two points on different curves");
    };

    switch (normalizeInfinity(point1), normalizeInfinity(point2)) {
      case (#infinity(curve), #infinity(_)) #infinity(curve);
      case (#infinity(_), _) point2;
      case (_, #infinity(_)) point1;
      case (#point(X1, Y1, Z1, curve), #point(X2, Y2, Z2, _)) {
        let (X3, Y3, Z3) = _add(
          X1.value,
          Y1.value,
          Z1.value,
          X2.value,
          Y2.value,
          Z2.value,
          curve.a,
          curve.p,
        );
        if (Y3 == 0 or Z3 == 0) {
          #infinity(curve);
        } else {
          #point(curve.Fp(X3), curve.Fp(Y3), curve.Fp(Z3), curve);
        };
      };
    };
  };

  func doDouble(X1 : Nat, Y1 : Nat, Z1 : Nat, a : Nat, p : Nat) : Coords {
    if (Z1 == 1) {
      return doubleWithZ1(X1, Y1, a, p);
    };
    if (Y1 == 0 or Z1 == 0) {
      return (0, 0, 0);
    };

    let XX = fsqr(X1, p);
    let YY = fsqr(Y1, p);
    let YYYY = fsqr(YY, p);
    let ZZ = fsqr(Z1, p);
    // S = 2 * ((X1 + YY)^2 - XX - YYYY)
    let S = fdbl(fsub(fsub(fsqr(fadd(X1, YY, p), p), XX, p), YYYY, p), p);
    // M = 3 * XX + a * ZZ^2
    var M = fadd(fdbl(XX, p), XX, p);
    if (a != 0) {
      M := fadd(M, fmul(a, fsqr(ZZ, p), p), p);
    };
    let T = fsub(fsqr(M, p), fdbl(S, p), p);
    // Y3 = M * (S - T) - 8 * YYYY
    let Y3 = fsub(fmul(M, fsub(S, T, p), p), fdbl(fdbl(fdbl(YYYY, p), p), p), p);
    // Z3 = (Y1 + Z1)^2 - YY - ZZ
    let Z3 = fsub(fsub(fsqr(fadd(Y1, Z1, p), p), YY, p), ZZ, p);

    (T, Y3, Z3);
  };

  func doubleWithZ1(X1 : Nat, Y1 : Nat, a : Nat, p : Nat) : Coords {
    if (Y1 == 0) {
      return (0, 0, 0);
    };

    let XX = fsqr(X1, p);
    let YY = fsqr(Y1, p);
    let YYYY = fsqr(YY, p);
    let S = fdbl(fsub(fsub(fsqr(fadd(X1, YY, p), p), XX, p), YYYY, p), p);
    let M = fadd(fadd(fdbl(XX, p), XX, p), a, p);
    let T = fsub(fsqr(M, p), fdbl(S, p), p);
    let Y3 = fsub(fmul(M, fsub(S, T, p), p), fdbl(fdbl(fdbl(YYYY, p), p), p), p);
    let Z3 = fdbl(Y1, p);
    (T, Y3, Z3);
  };

  func addWithEqZ(
    X1 : Nat,
    Y1 : Nat,
    Z1 : Nat,
    X2 : Nat,
    Y2 : Nat,
    a : Nat,
    p : Nat,
  ) : Coords {
    let dX = fsub(X2, X1, p);
    let dY = fsub(Y2, Y1, p);
    let A = fsqr(dX, p);
    let B = fmul(X1, A, p);
    let C = fmul(X2, A, p);
    let D = fsqr(dY, p);

    if (A == 0 and D == 0) {
      return doDouble(X1, Y1, Z1, a, p);
    };

    let X3 = fsub(fsub(D, B, p), C, p);
    // Y3 = dY * (B - X3) - Y1 * (C - B)
    let Y3 = fsub(fmul(dY, fsub(B, X3, p), p), fmul(Y1, fsub(C, B, p), p), p);
    let Z3 = fmul(Z1, dX, p);

    (X3, Y3, Z3);
  };

  func addWithZ1(
    X1 : Nat,
    Y1 : Nat,
    X2 : Nat,
    Y2 : Nat,
    a : Nat,
    p : Nat,
  ) : Coords {
    let H = fsub(X2, X1, p);
    let r = fdbl(fsub(Y2, Y1, p), p);

    if (H == 0 and r == 0) {
      return doubleWithZ1(X1, Y1, a, p);
    };

    let I = fdbl(fdbl(fsqr(H, p), p), p);
    let J = fmul(H, I, p);
    let V = fmul(X1, I, p);
    let X3 = fsub(fsub(fsqr(r, p), J, p), fdbl(V, p), p);
    // Y3 = r * (V - X3) - 2 * Y1 * J
    let Y3 = fsub(fmul(r, fsub(V, X3, p), p), fdbl(fmul(Y1, J, p), p), p);
    let Z3 = fdbl(H, p);

    (X3, Y3, Z3);
  };

  func addWithZ2Eq1(
    X1 : Nat,
    Y1 : Nat,
    Z1 : Nat,
    X2 : Nat,
    Y2 : Nat,
    a : Nat,
    p : Nat,
  ) : Coords {
    let Z1Z1 = fsqr(Z1, p);
    let U2 = fmul(X2, Z1Z1, p);
    let S2 = fmul(Y2, fmul(Z1, Z1Z1, p), p);
    let H = fsub(U2, X1, p);
    let r = fdbl(fsub(S2, Y1, p), p);

    if (r == 0 and H == 0) {
      return doubleWithZ1(X2, Y2, a, p);
    };

    let HH = fsqr(H, p);
    let I = fdbl(fdbl(HH, p), p);
    let J = fmul(H, I, p);
    let V = fmul(X1, I, p);
    let X3 = fsub(fsub(fsqr(r, p), J, p), fdbl(V, p), p);
    let Y3 = fsub(fmul(r, fsub(V, X3, p), p), fdbl(fmul(Y1, J, p), p), p);
    // Z3 = (Z1 + H)^2 - Z1Z1 - HH
    let Z3 = fsub(fsub(fsqr(fadd(Z1, H, p), p), Z1Z1, p), HH, p);

    (X3, Y3, Z3);
  };

  func addWithArbitraryZ(
    X1 : Nat,
    Y1 : Nat,
    Z1 : Nat,
    X2 : Nat,
    Y2 : Nat,
    Z2 : Nat,
    a : Nat,
    p : Nat,
  ) : Coords {
    let Z1Z1 = fsqr(Z1, p);
    let Z2Z2 = fsqr(Z2, p);
    let U1 = fmul(X1, Z2Z2, p);
    let U2 = fmul(X2, Z1Z1, p);
    let S1 = fmul(Y1, fmul(Z2, Z2Z2, p), p);
    let S2 = fmul(Y2, fmul(Z1, Z1Z1, p), p);
    let H = fsub(U2, U1, p);
    let r = fdbl(fsub(S2, S1, p), p);

    if (H == 0 and r == 0) {
      return doDouble(X1, Y1, Z1, a, p);
    };

    let I = fsqr(fdbl(H, p), p);
    let J = fmul(H, I, p);
    let V = fmul(U1, I, p);
    let X3 = fsub(fsub(fsqr(r, p), J, p), fdbl(V, p), p);
    let Y3 = fsub(fmul(r, fsub(V, X3, p), p), fdbl(fmul(S1, J, p), p), p);
    // Z3 = ((Z1 + Z2)^2 - Z1Z1 - Z2Z2) * H
    let Z3 = fmul(fsub(fsub(fsqr(fadd(Z1, Z2, p), p), Z1Z1, p), Z2Z2, p), H, p);

    (X3, Y3, Z3);
  };

  func _add(
    X1 : Nat,
    Y1 : Nat,
    Z1 : Nat,
    X2 : Nat,
    Y2 : Nat,
    Z2 : Nat,
    a : Nat,
    p : Nat,
  ) : Coords {

    if (Y1 == 0 or Z1 == 0) {
      return (X2, Y2, Z2);
    };

    if (Y2 == 0 or Z2 == 0) {
      return (X1, Y1, Z1);
    };

    if (Z1 == Z2) {
      if (Z1 == 1) {
        return addWithZ1(X1, Y1, X2, Y2, a, p);
      };
      return addWithEqZ(X1, Y1, Z1, X2, Y2, a, p);
    };

    if (Z1 == 1) {
      return addWithZ2Eq1(X2, Y2, Z2, X1, Y1, a, p);
    };

    if (Z2 == 1) {
      return addWithZ2Eq1(X1, Y1, Z1, X2, Y2, a, p);
    };

    return addWithArbitraryZ(X1, Y1, Z1, X2, Y2, Z2, a, p);
  };

  // Normalizes infinity point of the form #point (_, _, 0, _) to #infinity.
  func normalizeInfinity(point : Point) : Point {
    if (isInfinity(point)) {
      #infinity(getCurve(point));
    } else {
      point;
    };
  };

  // Extracts the curve from the given point.
  func getCurve(point : Point) : Curves.Curve {
    switch (point) {
      case (#infinity(curve)) curve;
      case (#point(_, _, _, curve)) curve;
    };
  };
};
