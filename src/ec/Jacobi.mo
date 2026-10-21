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

import Array "mo:core/Array";
import Int "mo:core/Int";
import Nat "mo:core/Nat";
import Runtime "mo:core/Runtime";
import VarArray "mo:core/VarArray";

import Affine "Affine";
import Curves "Curves";
import Field "Field";
import BaseFp "Fp";
import Numbers "Numbers";
import Secp256k1Generator "Secp256k1Generator";

module {
  type Fp = BaseFp.Fp;

  // Internal Jacobian coordinates: canonical residues in [0, p). A point
  // with Y = 0 or Z = 0 is the point at infinity.
  type Coords = (Nat, Nat, Nat);

  // Window width of the wNAF digits in GLV scalar multiplication.
  let GLV_WINDOW : Nat = 5;

  // Field.mul folds instead of dividing for the secp256k1 prime.
  func fmul(a : Nat, b : Nat, p : Nat) : Nat = Field.mul(a, b, p);
  func fsqr(a : Nat, p : Nat) : Nat = Field.mul(a, a, p);
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
          case (?glv) return wnafSum(pointTerms(x2.value, y2.value, other, glv, curve), curve);
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

  // One term `k * Q` of a multi-scalar multiplication: the wNAF digits of
  // |k|, a table of the odd multiples Q, 3Q, ..., (2^(w-1) - 1)Q, and whether
  // k is negative.
  type WnafTerm = {
    digits : [Int];
    table : [Coords];
    negative : Bool;
  };

  // Splits `scalar mod r` into `(k1, k2)` with `k1 + lambda * k2 == scalar`
  // (mod r) and both halves roughly half the bit-length of r. Returns null
  // if `scalar mod r == 0`.
  func glvSplit(scalar : Nat, glv : Curves.Glv, curve : Curves.Curve) : ?(Int, Int) {
    let n : Int = curve.r;
    let k : Int = scalar % curve.r;
    if (k == 0) {
      return null;
    };
    let halfN : Int = n / 2;

    // Both `b2` and `-b1` are positive for valid GLV bases, so the numerators
    // are non-negative and Motoko's truncating Int division yields rounding
    // to nearest (with halves rounded away from zero, which is acceptable).
    let c1 : Int = (glv.b2 * k + halfN) / n;
    let c2 : Int = (-glv.b1 * k + halfN) / n;
    let k1 : Int = k - c1 * glv.a1 - c2 * glv.a2;
    let k2 : Int = -c1 * glv.b1 - c2 * glv.b2;
    ?(k1, k2);
  };

  // The two wNAF terms `k1 * T[0] + k2 * U[0]` for the GLV split of
  // `scalar`, given tables T of the odd multiples of a point P and U of
  // phi(P), built for wNAF width `window`.
  func splitTerms(
    scalar : Nat,
    table1 : [Coords],
    table2 : [Coords],
    window : Nat,
    glv : Curves.Glv,
    curve : Curves.Curve,
  ) : [WnafTerm] {
    let ?(k1, k2) = glvSplit(scalar, glv, curve) else return [];
    [
      {
        digits = Numbers.toWnaf(Int.abs(k1), window);
        table = table1;
        negative = k1 < 0;
      },
      {
        digits = Numbers.toWnaf(Int.abs(k2), window);
        table = table2;
        negative = k2 < 0;
      },
    ];
  };

  // The two GLV terms `k1 * P + k2 * phi(P)` of `scalar * P` for the affine
  // point P = (x, y). Builds the tables of odd multiples on every call.
  func glvTerms(
    x : Nat,
    y : Nat,
    scalar : Nat,
    glv : Curves.Glv,
    curve : Curves.Curve,
  ) : [WnafTerm] {
    let (a, fp) = (curve.a, curve.p);

    // Odd multiples of P, and their images under
    // phi(X, Y, Z) = (beta * X, Y, Z).
    let tableSize = 2 ** (GLV_WINDOW - 2 : Nat);
    let table1 = VarArray.repeat<Coords>((x, y, 1), tableSize);
    let twoP = doubleWithZ1(x, y, a, fp);
    for (i in Nat.range(1, tableSize)) {
      let q = table1[i - 1];
      table1[i] := _add(q.0, q.1, q.2, twoP.0, twoP.1, twoP.2, a, fp);
    };
    let beta = glv.beta % fp;
    let table2 = Array.tabulate<Coords>(
      tableSize,
      func(i) {
        let q = table1[i];
        (fmul(beta, q.0, fp), q.1, q.2);
      },
    );
    splitTerms(scalar, table1.toArray(), table2, GLV_WINDOW, glv, curve);
  };

  // True if (x, y) is the generator of secp256k1, for which precomputed
  // tables exist.
  func isSecp256k1Generator(x : Nat, y : Nat, curve : Curves.Curve) : Bool {
    x == Curves.secp256k1.gx and y == Curves.secp256k1.gy and Curves.isEqual(curve, Curves.secp256k1);
  };

  // The four terms of `scalar * G` for the secp256k1 generator G: each GLV
  // half k is split once more into `kLow + 2^shift * kHigh`, against the
  // precomputed tables of G, H = 2^shift * G and their images under phi. The
  // pieces have about half the digits, so the loop needs about half the
  // doublings.
  func generatorTerms(scalar : Nat, glv : Curves.Glv, curve : Curves.Curve) : [WnafTerm] {
    let ?(k1, k2) = glvSplit(scalar, glv, curve) else return [];
    let window = Secp256k1Generator.window;
    let shift = Secp256k1Generator.shift.toNat32();
    func pieces(k : Int, low : [Coords], high : [Coords]) : [WnafTerm] {
      let abs = Int.abs(k);
      let kHigh = Nat.bitshiftRight(abs, shift);
      let kLow : Nat = abs - Nat.bitshiftLeft(kHigh, shift);
      [
        { digits = Numbers.toWnaf(kLow, window); table = low; negative = k < 0 },
        {
          digits = Numbers.toWnaf(kHigh, window);
          table = high;
          negative = k < 0;
        },
      ];
    };
    pieces(k1, Secp256k1Generator.multiples, Secp256k1Generator.shiftedMultiples).concat(
      pieces(k2, Secp256k1Generator.phiMultiples, Secp256k1Generator.phiShiftedMultiples)
    );
  };

  // The GLV terms of `scalar * P` for the affine point P = (x, y), using the
  // precomputed tables if P is the secp256k1 generator.
  func pointTerms(
    x : Nat,
    y : Nat,
    scalar : Nat,
    glv : Curves.Glv,
    curve : Curves.Curve,
  ) : [WnafTerm] {
    if (isSecp256k1Generator(x, y, curve)) {
      generatorTerms(scalar, glv, curve);
    } else {
      glvTerms(x, y, scalar, glv, curve);
    };
  };

  // Computes the sum of all `terms` with a Straus/Shamir-style interleaved
  // wNAF loop: the terms share one doubling per digit position, and each
  // non-zero digit adds one table entry.
  func wnafSum(terms : [WnafTerm], curve : Curves.Curve) : Point {
    let (a, fp) = (curve.a, curve.p);
    var len = 0;
    for (term in terms.values()) {
      if (term.digits.size() > len) len := term.digits.size();
    };
    if (len == 0) {
      return #infinity(curve);
    };

    var acc : Coords = (0, 0, 1);
    for (i in Nat.rangeByInclusive(len - 1, 0, -1)) {
      acc := doDouble(acc.0, acc.1, acc.2, a, fp);
      for (term in terms.values()) {
        if (i < term.digits.size()) {
          let d = term.digits[i];
          if (d != 0) {
            let q = term.table[Int.abs(d) / 2];
            let qy = if ((d < 0) != term.negative) fsub(0, q.1, fp) else q.1;
            acc := _add(acc.0, acc.1, acc.2, q.0, qy, q.2, a, fp);
          };
        };
      };
    };
    if (acc.1 == 0 or acc.2 == 0) {
      return #infinity(curve);
    };
    #point(curve.Fp(acc.0), curve.Fp(acc.1), curve.Fp(acc.2), curve);
  };

  /// Computes `a * point1 + b * point2`.
  ///
  /// Gives the same result as `add(mul(point1, a), mul(point2, b))`. On
  /// curves with GLV parameters (secp256k1) it is faster, because both
  /// multiplications share one doubling per bit of the half-length scalars,
  /// and a point that is the secp256k1 generator uses precomputed tables.
  /// This is the operation at the heart of ECDSA verification.
  ///
  /// Traps with `"Cannot add two points on different curves"` when
  /// `point1` and `point2` belong to different curves. Otherwise never
  /// traps; zero scalars and points at infinity are handled.
  public func mulAdd(point1 : Point, a : Nat, point2 : Point, b : Nat) : Point {
    let curve = getCurve(point1);
    if (not Curves.isEqual(curve, getCurve(point2))) {
      Runtime.trap("Cannot add two points on different curves");
    };
    let ?glv = curve.glv else return add(mul(point1, a), mul(point2, b));

    func terms(point : Point, scalar : Nat) : [WnafTerm] {
      switch (scale(point)) {
        case (#infinity(_)) [];
        case (#point(x, y, _, _)) pointTerms(x.value, y.value, scalar, glv, curve);
      };
    };
    let terms1 = terms(point1, a);
    let terms2 = terms(point2, b);
    wnafSum(terms1.concat(terms2), curve);
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
    // S = 4 * X1 * YY
    let S = fdbl(fdbl(fmul(X1, YY, p), p), p);
    // M = 3 * XX + a * Z1^4; for a = 0 (secp256k1) Z1^2 isn't needed.
    var M = fadd(fdbl(XX, p), XX, p);
    if (a != 0) {
      M := fadd(M, fmul(a, fsqr(fsqr(Z1, p), p), p), p);
    };
    let T = fsub(fsqr(M, p), fdbl(S, p), p);
    // Y3 = M * (S - T) - 8 * YYYY
    let Y3 = fsub(fmul(M, fsub(S, T, p), p), fdbl(fdbl(fdbl(YYYY, p), p), p), p);
    // Z3 = 2 * Y1 * Z1
    let Z3 = fdbl(fmul(Y1, Z1, p), p);

    (T, Y3, Z3);
  };

  func doubleWithZ1(X1 : Nat, Y1 : Nat, a : Nat, p : Nat) : Coords {
    if (Y1 == 0) {
      return (0, 0, 0);
    };

    let XX = fsqr(X1, p);
    let YY = fsqr(Y1, p);
    let YYYY = fsqr(YY, p);
    let S = fdbl(fdbl(fmul(X1, YY, p), p), p);
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

  // P1 + P2 for an affine P2 (Z2 = 1): 8 multiplications and 3 squarings,
  // in the H^3 form that needs few additions and subtractions.
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
    let r = fsub(S2, Y1, p);

    if (H == 0) {
      return if (r == 0) doubleWithZ1(X2, Y2, a, p) else (0, 0, 0);
    };

    let HH = fsqr(H, p);
    let HHH = fmul(H, HH, p);
    let V = fmul(X1, HH, p);
    // X3 = r^2 - H^3 - 2 * V
    let X3 = fsub(fsub(fsub(fsqr(r, p), HHH, p), V, p), V, p);
    // Y3 = r * (V - X3) - Y1 * H^3
    let Y3 = fsub(fmul(r, fsub(V, X3, p), p), fmul(Y1, HHH, p), p);
    let Z3 = fmul(Z1, H, p);

    (X3, Y3, Z3);
  };

  // P1 + P2 for arbitrary Z1, Z2: 12 multiplications and 4 squarings, in
  // the same H^3 form as addWithZ2Eq1.
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
    let r = fsub(S2, S1, p);

    if (H == 0) {
      return if (r == 0) doDouble(X1, Y1, Z1, a, p) else (0, 0, 0);
    };

    let HH = fsqr(H, p);
    let HHH = fmul(H, HH, p);
    let V = fmul(U1, HH, p);
    let X3 = fsub(fsub(fsub(fsqr(r, p), HHH, p), V, p), V, p);
    let Y3 = fsub(fmul(r, fsub(V, X3, p), p), fmul(S1, HHH, p), p);
    let Z3 = fmul(fmul(Z1, Z2, p), H, p);

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
