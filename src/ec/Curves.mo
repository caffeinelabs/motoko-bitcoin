import Fp "Fp";

module {
  // Parameters for the GLV endomorphism `phi(x, y) = (beta * x, y)`, which
  // satisfies `phi(P) = lambda * P` on the curve. The basis `(a1, b1), (a2, b2)`
  // is used to decompose a scalar `k mod r` into a pair `(k1, k2)` of roughly
  // half the bit-length such that `k = k1 + k2 * lambda mod r`.
  public type Glv = {
    beta : Nat;
    lambda : Nat;
    a1 : Int;
    b1 : Int;
    a2 : Int;
    b2 : Int;
  };

  public type Curve = {
    p : Nat;
    // Order (number of points on the curve)
    r : Nat;
    // a and b from  y^2 = x^3 + ax + b
    a : Nat;
    b : Nat;
    // Generator point
    gx : Nat;
    gy : Nat;
    Fp : (Nat) -> Fp.Fp;
    // Optional GLV endomorphism parameters for fast scalar multiplication.
    glv : ?Glv;
  };

  public let secp256k1 : Curve = {
    p = 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f;
    r = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141;
    a = 0;
    b = 7;
    gx = 0x79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798;
    gy = 0x483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8;
    Fp = func(value : Nat) : Fp.Fp {
      Fp.Fp(value, secp256k1.p);
    };
    glv = ?{
      beta = 0x7ae96a2b657c07106e64479eac3434e99cf0497512f58995c1396c28719501ee;
      lambda = 0x5363ad4cc05c30e0a5261c028812645a122e22ea20816678df02967c1b23bd72;
      a1 = 0x3086d221a7d46bcde86c90e49284eb15;
      b1 = -0xe4437ed6010e88286f547fa90abfe4c3;
      a2 = 0x114ca50f7a8e2f3f657c1108d9d44cfd8;
      b2 = 0x3086d221a7d46bcde86c90e49284eb15;
    };
  };

  public func isEqual(curve1 : Curve, curve2 : Curve) : Bool {
    curve1.p == curve2.p and curve1.a == curve2.a and curve1.b == curve2.b and curve1.gx == curve2.gx and curve1.gy == curve2.gy
  };
};
