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

  public type Point = {
    #infinity : Curves.Curve;
    #point : (Fp, Fp, Fp, Curves.Curve);
  };

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

  // Serialize given point to bytes in SEC-1 format.
  public func toBytes(point : Point, compressed : Bool) : [Nat8] {
    Affine.toBytes(toAffine(point), compressed);
  };

  // Check if the given point is valid.
  public func isOnCurve(point : Point) : Bool {
    Affine.isOnCurve(toAffine(point));
  };

  // Convert given point from affine coordinates to jacobi coordinates
  public func fromAffine(point : Affine.Point) : Point {
    switch point {
      case (#infinity(curve)) #infinity(curve);
      case (#point(x, y, curve)) #point(x, y, curve.Fp(1), curve);
    };
  };

  // Create a jacobi point from the given coordinates.
  // Returns null if the point is not valid.
  public func fromNat(x : Nat, y : Nat, z : Nat, curve : Curves.Curve) : ?Point {
    ?(#point(curve.Fp(x), curve.Fp(y), curve.Fp(z), curve));
  };

  // Return the base point of the given curve.
  public func base(curve : Curves.Curve) : Point {
    #point(curve.Fp(curve.gx), curve.Fp(curve.gy), curve.Fp(1), curve);
  };

  // Check if the two given jacobi points are equal.
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

  // Check if the given point is the point at infinity.
  public func isInfinity(point : Point) : Bool {
    switch point {
      case (#infinity(_)) true;
      case (#point(_, _, z, curve)) z.isEqual(curve.Fp(0));
    };
  };

  // Convert the given jacobi point to affine.
  public func toAffine(point : Point) : Affine.Point {
    let scaledPoint = scale(point);
    switch scaledPoint {
      case (#infinity(curve)) #infinity(curve);
      case (#point(x, y, _, curve)) #point(x, y, curve);
    };
  };

  // Invert the given point on the x-axis.
  public func neg(point : Point) : Point {
    switch (normalizeInfinity(point)) {
      case (#infinity(curve)) #infinity(curve);
      case (#point(x, y, z, curve)) #point(x, y.neg(), z, curve);
    };
  };

  // Normalize the given point such that z = 1.
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

  // Return double of the given point.
  public func double(point : Point) : Point {
    switch (normalizeInfinity(point)) {
      case (#infinity(curve)) #infinity(curve);
      case (#point(x, y, z, curve)) {
        let (x2, y2, z2) = doDouble(x.value, y.value, z.value, curve.a, curve.p);
        #point(
          fpFromInt(x2, curve),
          fpFromInt(y2, curve),
          fpFromInt(z2, curve),
          curve,
        );
      };
    };
  };

  // Multiply the given point by the given scalar value.
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
        var p : (Int, Int, Int) = (0, 0, 1);
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
        #point(fpFromInt(p.0, curve), fpFromInt(p.1, curve), fpFromInt(p.2, curve), curve);
      };
    };
  };

  // Scalar multiplication using the GLV endomorphism. Decomposes the scalar
  // `k mod r` into `(k1, k2)` such that `k1 + lambda * k2 == k (mod r)` and
  // both halves are roughly half the bit-length of `r`. Then computes
  // `k1 * P + k2 * phi(P)` with a Straus/Shamir-style interleaved-NAF loop,
  // where `phi(X, Y, Z) = (beta * X, Y, Z)` in Jacobian coordinates.
  // Caller guarantees `(x, y)` is the affine representation (Z=1) of P and
  // that `scalar != 0`.
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

    var p : (Int, Int, Int) = (0, 0, 1);
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
    #point(fpFromInt(p.0, curve), fpFromInt(p.1, curve), fpFromInt(p.2, curve), curve);
  };

  // Multiply the base point of the given curve by the given scalar value.
  public func mulBase(other : Nat, curve : Curves.Curve) : Point {
    mul(base(curve), other);
  };

  // Add the given two points.
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
          #point(
            fpFromInt(X3, curve),
            fpFromInt(Y3, curve),
            fpFromInt(Z3, curve),
            curve,
          );
        };
      };
    };
  };

  func doDouble(X1 : Int, Y1 : Int, Z1 : Int, a : Nat, p : Nat) : (Int, Int, Int) {
    if (Z1 == 1) {
      return doubleWithZ1(X1, Y1, a, p);
    };
    if (Y1 == 0 or Z1 == 0) {
      return (0, 0, 0);
    };

    let (XX, YY) = (X1 * X1 % p, Y1 * Y1 % p);
    let YYYY : Int = YY * YY % p;
    let ZZ : Int = Z1 * Z1 % p;
    let S : Int = (X1 + YY) |> 2 * (_ * _ - XX - YYYY) % p;
    let M : Int = if (a == 0) { 3 * XX % p } else {
      (3 * XX + a * ZZ * ZZ) % p;
    };
    let T : Int = (M * M - 2 * S) % p;

    let Y3 = (M * (S - T) - 8 * YYYY) % p;
    let Z3 = (Y1 + Z1) |> (_ * _ - YY - ZZ) % p;

    return (T, Y3, Z3);
  };

  func doubleWithZ1(X1 : Int, Y1 : Int, a : Nat, p : Nat) : (Int, Int, Int) {
    if (Y1 == 0) {
      return (0, 0, 0);
    };

    let (XX, YY) = (X1 * X1 % p, Y1 * Y1 % p);
    let YYYY : Int = YY * YY % p;
    let S : Int = 2 * ((X1 + YY) ** 2 - XX - YYYY) % p;
    let M : Int = 3 * XX + a;
    let T : Int = (M * M - 2 * S) % p;
    let Y3 : Int = (M * (S - T) - 8 * YYYY) % p;
    let Z3 : Int = 2 * Y1 % p;
    return (T, Y3, Z3);
  };

  func addWithEqZ(
    X1 : Int,
    Y1 : Int,
    Z1 : Int,
    X2 : Int,
    Y2 : Int,
    a : Nat,
    p : Nat,
  ) : (Int, Int, Int) {

    let A : Int = (X2 - X1) ** 2 % p;
    let B : Int = X1 * A % p;
    let C : Int = X2 * A % p;
    let D : Int = (Y2 - Y1) ** 2 % p;

    if (A == 0 and D == 0) {
      return doDouble(X1, Y1, Z1, a, p);
    };

    let X3 : Int = (D - B - C) % p;
    let Y3 : Int = ((Y2 - Y1) * (B - X3) - Y1 * (C - B)) % p;
    let Z3 : Int = Z1 * (X2 - X1) % p;

    return (X3, Y3, Z3);
  };

  func addWithZ1(
    X1 : Int,
    Y1 : Int,
    X2 : Int,
    Y2 : Int,
    a : Nat,
    p : Nat,
  ) : (Int, Int, Int) {
    let H : Int = X2 - X1;
    let HH : Int = H * H;
    let I : Int = 4 * HH % p;
    let J : Int = H * I;
    let r : Int = 2 * (Y2 - Y1);

    if (H == 0 and r == 0) {
      return doubleWithZ1(X1, Y1, a, p);
    };

    let V : Int = X1 * I;
    let X3 : Int = (r * r - J - 2 * V) % p;
    let Y3 : Int = (r * (V - X3) - 2 * Y1 * J) % p;
    let Z3 : Int = 2 * H % p;

    return (X3, Y3, Z3);
  };

  func addWithZ2Eq1(
    X1 : Int,
    Y1 : Int,
    Z1 : Int,
    X2 : Int,
    Y2 : Int,
    a : Nat,
    p : Nat,
  ) : (Int, Int, Int) {

    let Z1Z1 : Int = Z1 * Z1 % p;
    let (U2, S2) = (X2 * Z1Z1 % p, Y2 * Z1 * Z1Z1 % p);
    let H : Int = (U2 - X1) % p;
    let HH : Int = H * H % p;
    let I : Int = 4 * HH % p;
    let J : Int = H * I;
    let r : Int = 2 * (S2 - Y1) % p;

    if (r == 0 and H == 0) {
      return doubleWithZ1(X2, Y2, a, p);
    };

    let V : Int = X1 * I;
    let X3 = ((r * r) - J - (2 * V)) % p;
    let Y3 = (r * (V - X3) - 2 * Y1 * J) % p;
    let Z3 = ((Z1 + H) ** 2 - Z1Z1 - HH) % p;

    return (X3, Y3, Z3);
  };

  func addWithArbitraryZ(
    X1 : Int,
    Y1 : Int,
    Z1 : Int,
    X2 : Int,
    Y2 : Int,
    Z2 : Int,
    a : Nat,
    p : Nat,
  ) : (Int, Int, Int) {

    let Z1Z1 : Int = Z1 * Z1 % p;
    let Z2Z2 : Int = Z2 * Z2 % p;
    let U1 : Int = X1 * Z2Z2 % p;
    let U2 : Int = X2 * Z1Z1 % p;
    let S1 : Int = Y1 * Z2 * Z2Z2 % p;
    let S2 : Int = Y2 * Z1 * Z1Z1 % p;
    let H : Int = U2 - U1;
    let r : Int = 2 * (S2 - S1) % p;

    if (H == 0 and r == 0) {
      return doDouble(X1, Y1, Z1, a, p);
    };

    let I : Int = 4 * H * H % p;
    let J : Int = H * I % p;
    let V = U1 * I;
    let X3 : Int = (r * r - J - 2 * V) % p;
    let Y3 : Int = (r * (V - X3) - 2 * S1 * J) % p;
    let Z3 : Int = ((Z1 + Z2) ** 2 - Z1Z1 - Z2Z2) * H % p;

    return (X3, Y3, Z3);
  };

  func _add(
    X1 : Int,
    Y1 : Int,
    Z1 : Int,
    X2 : Int,
    Y2 : Int,
    Z2 : Int,
    a : Nat,
    p : Nat,
  ) : (Int, Int, Int) {

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

  func fpFromInt(value : Int, curve : Curves.Curve) : Fp {
    let mod : Int = value % curve.p;
    if (mod < 0) {
      curve.Fp(Int.abs(mod + curve.p));
    } else {
      curve.Fp(Int.abs(mod));
    };
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
