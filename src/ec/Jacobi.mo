/// Jacobian-coordinate elliptic curve operations.
///
/// Intended for public-data operations only; not constant-time for secret
/// inputs.
///
/// Points of order 2 are not supported. Such a point has y = 0, which the
/// arithmetic treats as the point at infinity. Only curves with an even
/// number of points have them; secp256k1 and secp256r1 don't. On a curve
/// that has them, `add`, `double`, `mul`, `mulBase` and `mulAdd` can return
/// wrong points without trapping, not only when the result has order 2 but
/// also when an intermediate result does.
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
  type Modulus = Field.Modulus;

  // Window width of the wNAF digits in scalar multiplication, for the GLV
  // halves on curves with an endomorphism and for full scalars on others.
  let WNAF_WINDOW : Nat = 5;

  // Field.mul folds instead of dividing for the secp256k1 prime.
  func fmul(a : Nat, b : Nat, m : Modulus) : Nat = Field.mulMod(a, b, m);
  func fsqr(a : Nat, m : Modulus) : Nat = Field.mulMod(a, a, m);
  func fadd(a : Nat, b : Nat, m : Modulus) : Nat {
    let s = a + b;
    if (s >= m.0) s - m.0 else s;
  };
  func fsub(a : Nat, b : Nat, m : Modulus) : Nat = if (a >= b) a - b else a + m.0 - b;
  func fdbl(a : Nat, m : Modulus) : Nat = fadd(a, a, m);

  /// Jacobian point representation. The arithmetic treats a `#point` with
  /// y = 0 as infinity (see the module description).
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

  /// Returns true if `point` is at infinity, that is `#infinity` or z = 0.
  /// A point of order 2 (y = 0, z != 0) isn't reported as infinity here,
  /// although the arithmetic treats it as infinity.
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
        let (x2, y2, z2) = doDouble(x.value, y.value, z.value, curve.a, Field.modulus(curve.p));
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
        let terms = switch (pointTerms(x2.value, y2.value, other, curve)) {
          case (?terms) terms;
          // NAF, adding only P itself.
          case null [{
            digits = Numbers.toWnaf(other, 2);
            table = [(x2.value, y2.value, 1)];
            negative = false;
          }];
        };
        wnafSum(terms, curve);
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
  ) : ?[WnafTerm] {
    let m = Field.modulus(curve.p);
    // Odd multiples of P with one shared Z if possible.
    let size = 2 ** (WNAF_WINDOW - 2 : Nat);
    let table1 = switch (coZOddMultiples(x, y, size, curve.a, m)) {
      case (?table) table;
      case null {
        let ?table = oddMultiples(x, y, curve) else return null;
        table;
      };
    };
    // Their images under phi(X, Y, Z) = (beta * X, Y, Z).
    let beta = glv.beta % m.0;
    let table2 = table1.map<Coords, Coords>(func(q) = (fmul(beta, q.0, m), q.1, q.2));
    ?splitTerms(scalar, table1, table2, WNAF_WINDOW, glv, curve);
  };

  // The odd multiples P, 3P, ..., (2^(WNAF_WINDOW - 1) - 1)P of the affine
  // point P = (x, y), in Jacobian coordinates: one doubling and
  // 2^(WNAF_WINDOW - 2) - 1 additions.
  //
  // Returns null if P, 2P or an entry is a point of order 2. Its Y is 0,
  // which the formulas read as infinity, so the entries after it would be
  // wrong. Only curves of even order have such points.
  func oddMultiples(x : Nat, y : Nat, curve : Curves.Curve) : ?[Coords] {
    let (a, m) = (curve.a, Field.modulus(curve.p));
    let tableSize = 2 ** (WNAF_WINDOW - 2 : Nat);
    let table = VarArray.repeat<Coords>((x, y, 1), tableSize);
    let twoP = doubleWithZ1(x, y, a, m);
    for (i in Nat.range(1, tableSize)) {
      let q = table[i - 1];
      table[i] := _add(q.0, q.1, q.2, twoP.0, twoP.1, twoP.2, a, m);
    };
    func orderTwo(q : Coords) : Bool = q.1 == 0 and q.2 != 0;
    if (orderTwo(twoP) or table.any(orderTwo)) null else ?table.toArray();
  };

  // The odd multiples P, 3P, ..., (2 * size - 1)P of the affine point
  // P = (x, y), all with the same Z, without a field inversion (as in
  // libsecp256k1). On the isomorphic curve that scales affine coordinates
  // by (dz^2, dz^3), where 2P = (dx, dy, dz), 2P is affine, so each entry
  // takes a mixed addition, and a backward pass brings all entries to the
  // last Z. Returns null if an addition meets equal x coordinates, which
  // only points of small order do, or if an entry has order 2.
  func coZOddMultiples(x : Nat, y : Nat, size : Nat, a : Nat, m : Modulus) : ?[Coords] {
    let (dx, dy, dz) = doubleWithZ1(x, y, a, m);
    if (dz == 0) return null;
    let dz2 = fsqr(dz, m);
    let table = VarArray.repeat<Coords>((fmul(x, dz2, m), fmul(y, fmul(dz2, dz, m), m), 1), size);
    // h[i] = Z[i] / Z[i - 1]
    let h = VarArray.repeat<Nat>(1, size);
    for (i in Nat.range(1, size)) {
      let (X1, Y1, Z1) = table[i - 1];
      h[i] := fsub(fmul(dx, fsqr(Z1, m), m), X1, m);
      if (h[i] == 0) return null;
      table[i] := addWithZ2Eq1(X1, Y1, Z1, dx, dy, 1, a, m);
    };
    // Entry i - 1 is scaled by f = h[i] * ... * h[size - 1].
    var f = 1;
    for (i in Nat.rangeByInclusive(size - 1, 1, -1)) {
      f := fmul(f, h[i], m);
      let (X, Y, _) = table[i - 1];
      let ff = fsqr(f, m);
      table[i - 1] := (fmul(X, ff, m), fmul(Y, fmul(ff, f, m), m), 0);
    };
    // An entry of order 2 has Y = 0, which the formulas read as infinity.
    if (table.any(func(q : Coords) : Bool = q.1 == 0)) return null;
    // On the original curve, the shared Z is the last Z times dz.
    let z = fmul(table[size - 1].2, dz, m);
    ?Array.tabulate<Coords>(size, func(i) = (table[i].0, table[i].1, z));
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

  // The wNAF terms of `scalar * P` for the affine point P = (x, y). On
  // curves with GLV parameters these are the GLV terms, using the
  // precomputed tables if P is the secp256k1 generator. On other curves it
  // is one term with the full scalar against the odd multiples of P.
  // Returns null if the table of odd multiples can't be built (see
  // `oddMultiples`).
  func pointTerms(x : Nat, y : Nat, scalar : Nat, curve : Curves.Curve) : ?[WnafTerm] {
    switch (curve.glv) {
      case (?glv) {
        if (isSecp256k1Generator(x, y, curve)) {
          ?generatorTerms(scalar, glv, curve);
        } else {
          glvTerms(x, y, scalar, glv, curve);
        };
      };
      case null {
        if (scalar == 0) return ?[];
        let ?table = oddMultiples(x, y, curve) else return null;
        ?[{
          digits = Numbers.toWnaf(scalar, WNAF_WINDOW);
          table;
          negative = false;
        }];
      };
    };
  };

  // Computes the sum of all `terms` with a Straus/Shamir-style interleaved
  // wNAF loop: the terms share one doubling per digit position, and each
  // non-zero digit adds one table entry.
  //
  // Tables whose entries share one Z (affine tables have Z = 1) take mixed
  // additions. On curves with a = 0, whose formulas don't depend on the
  // curve constants, the loop runs on the isomorphic curve on which the
  // entries with the shared Z zg != 1 of `coZOddMultiples` are affine; there
  // affine entries have Z = 1 / zg, and the result's Z is multiplied by zg.
  func wnafSum(terms : [WnafTerm], curve : Curves.Curve) : Point {
    let (a, m) = (curve.a, Field.modulus(curve.p));
    var len = 0;
    for (term in terms.values()) {
      if (term.digits.size() > len) len := term.digits.size();
    };
    if (len == 0) {
      return #infinity(curve);
    };

    // The Z shared by all entries of each table, if any.
    let zs = terms.map<WnafTerm, ?Nat>(
      func(term) {
        let z = term.table[0].2;
        if (term.table.all(func(q : Coords) : Bool = q.2 == z)) ?z else null;
      }
    );
    var zg = 1;
    if (a == 0) {
      label search for (z in zs.values()) {
        switch z {
          case (?z) if (z != 1) { zg := z; break search };
          case null {};
        };
      };
    };
    // The inverse of an entry's Z on the isomorphic curve, or null for
    // entries added as general Jacobian points.
    func zinv(z : ?Nat) : ?Nat = switch z {
      case (?1) ?zg;
      case (?z) if (z == zg) ?1 else null;
      case null null;
    };
    // With tables of two different shared Z, stay on the original curve.
    if (zs.any(func(z : ?Nat) : Bool = zinv(z) == null)) zg := 1;
    let zinvs = zs.map(zinv);
    let zg2 = fsqr(zg, m);
    let zg3 = fmul(zg2, zg, m);

    var acc : Coords = (0, 0, 1);
    for (i in Nat.rangeByInclusive(len - 1, 0, -1)) {
      acc := doDouble(acc.0, acc.1, acc.2, a, m);
      for (t in terms.keys()) {
        let term = terms[t];
        if (i < term.digits.size()) {
          let d = term.digits[i];
          if (d != 0) {
            let q = term.table[Int.abs(d) / 2];
            let qy = if ((d < 0) != term.negative) fsub(0, q.1, m) else q.1;
            acc := switch (zinvs[t]) {
              case null _add(acc.0, acc.1, acc.2, q.0, qy, q.2, a, m);
              case (?zi) {
                if (acc.1 != 0 and acc.2 != 0) {
                  addWithZ2Eq1(acc.0, acc.1, acc.2, q.0, qy, zi, a, m);
                } else {
                  // acc is infinity: the entry, as an affine point on the
                  // isomorphic curve.
                  if (zi == 1) (q.0, qy, 1) else (fmul(q.0, zg2, m), fmul(qy, zg3, m), 1);
                };
              };
            };
          };
        };
      };
    };
    if (acc.1 == 0 or acc.2 == 0) {
      return #infinity(curve);
    };
    let z = if (zg == 1) acc.2 else fmul(acc.2, zg, m);
    #point(curve.Fp(acc.0), curve.Fp(acc.1), curve.Fp(z), curve);
  };

  /// Computes `a * point1 + b * point2`.
  ///
  /// Gives the same result as `add(mul(point1, a), mul(point2, b))`, but
  /// faster, because both multiplications share one doubling per digit. On
  /// curves with GLV parameters (secp256k1) the scalars are split into
  /// half-length pieces first, and a point that is the secp256k1 generator
  /// uses precomputed tables. This is the operation at the heart of ECDSA
  /// verification.
  ///
  /// Traps with `"Cannot add two points on different curves"` when
  /// `point1` and `point2` belong to different curves. Otherwise never
  /// traps; zero scalars and points at infinity are handled.
  public func mulAdd(point1 : Point, a : Nat, point2 : Point, b : Nat) : Point {
    let curve = getCurve(point1);
    if (not Curves.isEqual(curve, getCurve(point2))) {
      Runtime.trap("Cannot add two points on different curves");
    };

    func terms(point : Point, scalar : Nat) : ?[WnafTerm] {
      switch (scale(point)) {
        case (#infinity(_)) ?[];
        case (#point(x, y, _, _)) pointTerms(x.value, y.value, scalar, curve);
      };
    };
    switch (terms(point1, a), terms(point2, b)) {
      case (?terms1, ?terms2) wnafSum(terms1.concat(terms2), curve);
      case _ add(mul(point1, a), mul(point2, b));
    };
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
          Field.modulus(curve.p),
        );
        if (Y3 == 0 or Z3 == 0) {
          #infinity(curve);
        } else {
          #point(curve.Fp(X3), curve.Fp(Y3), curve.Fp(Z3), curve);
        };
      };
    };
  };

  func doDouble(X1 : Nat, Y1 : Nat, Z1 : Nat, a : Nat, m : Modulus) : Coords {
    if (Z1 == 1) {
      return doubleWithZ1(X1, Y1, a, m);
    };
    if (Y1 == 0 or Z1 == 0) {
      return (0, 0, 0);
    };

    let YY = fsqr(Y1, m);
    let YYYY = fsqr(YY, m);
    // S = 4 * X1 * YY
    let S = fdbl(fdbl(fmul(X1, YY, m), m), m);
    // M = 3 * XX + a * Z1^4. For a = 0 (secp256k1) Z1 isn't needed; for
    // a = -3 (secp256r1 and the other NIST curves) it is
    // 3 * (X1 - ZZ) * (X1 + ZZ), which saves two squarings.
    let M = if (a == 0) {
      let XX = fsqr(X1, m);
      fadd(fdbl(XX, m), XX, m);
    } else if (a + 3 == m.0) {
      let ZZ = fsqr(Z1, m);
      let P = fmul(fsub(X1, ZZ, m), fadd(X1, ZZ, m), m);
      fadd(fdbl(P, m), P, m);
    } else {
      let XX = fsqr(X1, m);
      fadd(fadd(fdbl(XX, m), XX, m), fmul(a, fsqr(fsqr(Z1, m), m), m), m);
    };
    let T = fsub(fsqr(M, m), fdbl(S, m), m);
    // Y3 = M * (S - T) - 8 * YYYY
    let Y3 = fsub(fmul(M, fsub(S, T, m), m), fdbl(fdbl(fdbl(YYYY, m), m), m), m);
    // Z3 = 2 * Y1 * Z1
    let Z3 = fdbl(fmul(Y1, Z1, m), m);

    (T, Y3, Z3);
  };

  func doubleWithZ1(X1 : Nat, Y1 : Nat, a : Nat, m : Modulus) : Coords {
    if (Y1 == 0) {
      return (0, 0, 0);
    };

    let XX = fsqr(X1, m);
    let YY = fsqr(Y1, m);
    let YYYY = fsqr(YY, m);
    let S = fdbl(fdbl(fmul(X1, YY, m), m), m);
    let M = fadd(fadd(fdbl(XX, m), XX, m), a, m);
    let T = fsub(fsqr(M, m), fdbl(S, m), m);
    let Y3 = fsub(fmul(M, fsub(S, T, m), m), fdbl(fdbl(fdbl(YYYY, m), m), m), m);
    let Z3 = fdbl(Y1, m);
    (T, Y3, Z3);
  };

  func addWithEqZ(
    X1 : Nat,
    Y1 : Nat,
    Z1 : Nat,
    X2 : Nat,
    Y2 : Nat,
    a : Nat,
    m : Modulus,
  ) : Coords {
    let dX = fsub(X2, X1, m);
    let dY = fsub(Y2, Y1, m);
    let A = fsqr(dX, m);
    let B = fmul(X1, A, m);
    let C = fmul(X2, A, m);
    let D = fsqr(dY, m);

    if (A == 0 and D == 0) {
      return doDouble(X1, Y1, Z1, a, m);
    };

    let X3 = fsub(fsub(D, B, m), C, m);
    // Y3 = dY * (B - X3) - Y1 * (C - B)
    let Y3 = fsub(fmul(dY, fsub(B, X3, m), m), fmul(Y1, fsub(C, B, m), m), m);
    let Z3 = fmul(Z1, dX, m);

    (X3, Y3, Z3);
  };

  func addWithZ1(
    X1 : Nat,
    Y1 : Nat,
    X2 : Nat,
    Y2 : Nat,
    a : Nat,
    m : Modulus,
  ) : Coords {
    let H = fsub(X2, X1, m);
    let r = fdbl(fsub(Y2, Y1, m), m);

    if (H == 0 and r == 0) {
      return doubleWithZ1(X1, Y1, a, m);
    };

    let I = fdbl(fdbl(fsqr(H, m), m), m);
    let J = fmul(H, I, m);
    let V = fmul(X1, I, m);
    let X3 = fsub(fsub(fsqr(r, m), J, m), fdbl(V, m), m);
    // Y3 = r * (V - X3) - 2 * Y1 * J
    let Y3 = fsub(fmul(r, fsub(V, X3, m), m), fdbl(fmul(Y1, J, m), m), m);
    let Z3 = fdbl(H, m);

    (X3, Y3, Z3);
  };

  // P1 + P2 for P2 = (X2, Y2, 1 / zinv), usually affine (zinv = 1): 8
  // multiplications and 3 squarings, in the H^3 form that needs few
  // additions and subtractions. Another zinv costs one multiplication more
  // (libsecp256k1's gej_add_zinv_var).
  func addWithZ2Eq1(
    X1 : Nat,
    Y1 : Nat,
    Z1 : Nat,
    X2 : Nat,
    Y2 : Nat,
    zinv : Nat,
    a : Nat,
    m : Modulus,
  ) : Coords {
    let Z = if (zinv == 1) Z1 else fmul(Z1, zinv, m);
    let ZZ = fsqr(Z, m);
    let U2 = fmul(X2, ZZ, m);
    let S2 = fmul(Y2, fmul(Z, ZZ, m), m);
    let H = fsub(U2, X1, m);
    let r = fsub(S2, Y1, m);

    if (H == 0) {
      return if (r == 0) doDouble(X1, Y1, Z1, a, m) else (0, 0, 0);
    };

    let HH = fsqr(H, m);
    let HHH = fmul(H, HH, m);
    let V = fmul(X1, HH, m);
    // X3 = r^2 - H^3 - 2 * V
    let X3 = fsub(fsub(fsub(fsqr(r, m), HHH, m), V, m), V, m);
    // Y3 = r * (V - X3) - Y1 * H^3
    let Y3 = fsub(fmul(r, fsub(V, X3, m), m), fmul(Y1, HHH, m), m);
    let Z3 = fmul(Z1, H, m);

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
    m : Modulus,
  ) : Coords {
    let Z1Z1 = fsqr(Z1, m);
    let Z2Z2 = fsqr(Z2, m);
    let U1 = fmul(X1, Z2Z2, m);
    let U2 = fmul(X2, Z1Z1, m);
    let S1 = fmul(Y1, fmul(Z2, Z2Z2, m), m);
    let S2 = fmul(Y2, fmul(Z1, Z1Z1, m), m);
    let H = fsub(U2, U1, m);
    let r = fsub(S2, S1, m);

    if (H == 0) {
      return if (r == 0) doDouble(X1, Y1, Z1, a, m) else (0, 0, 0);
    };

    let HH = fsqr(H, m);
    let HHH = fmul(H, HH, m);
    let V = fmul(U1, HH, m);
    let X3 = fsub(fsub(fsub(fsqr(r, m), HHH, m), V, m), V, m);
    let Y3 = fsub(fmul(r, fsub(V, X3, m), m), fmul(S1, HHH, m), m);
    let Z3 = fmul(fmul(Z1, Z2, m), H, m);

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
    m : Modulus,
  ) : Coords {

    if (Y1 == 0 or Z1 == 0) {
      return (X2, Y2, Z2);
    };

    if (Y2 == 0 or Z2 == 0) {
      return (X1, Y1, Z1);
    };

    if (Z1 == Z2) {
      if (Z1 == 1) {
        return addWithZ1(X1, Y1, X2, Y2, a, m);
      };
      return addWithEqZ(X1, Y1, Z1, X2, Y2, a, m);
    };

    if (Z1 == 1) {
      return addWithZ2Eq1(X2, Y2, Z2, X1, Y1, 1, a, m);
    };

    if (Z2 == 1) {
      return addWithZ2Eq1(X1, Y1, Z1, X2, Y2, 1, a, m);
    };

    return addWithArbitraryZ(X1, Y1, Z1, X2, Y2, Z2, a, m);
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
