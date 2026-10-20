// secp256r1 (NIST P-256), for tests and benchmarks only: the package does
// not export it. It has no GLV endomorphism and a = -3, so it exercises the
// generic code paths that secp256k1 never takes.

import Curves "../../src/ec/Curves";
import Fp "../../src/ec/Fp";

module {
  public let curve : Curves.Curve = {
    p = 0xffffffff00000001000000000000000000000000ffffffffffffffffffffffff;
    r = 0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551;
    a = 0xffffffff00000001000000000000000000000000fffffffffffffffffffffffc;
    b = 0x5ac635d8aa3a93e7b3ebbd55769886bc651d06b0cc53b0f63bce3c3e27d2604b;
    gx = 0x6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296;
    gy = 0x4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5;
    Fp = func(value : Nat) : Fp.Fp {
      Fp.Fp(value, 0xffffffff00000001000000000000000000000000ffffffffffffffffffffffff);
    };
    glv = null;
  };
};
