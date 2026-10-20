import Bench "mo:bench-helper";

import Curves "../src/ec/Curves";
import Jacobi "../src/ec/Jacobi";

module {
  public func init() : Bench.V1 {
    let schema : Bench.Schema = {
      name = "EC operations with full-size scalars";
      description = "Public key decompression and scalar multiplication with 256-bit scalars on secp256k1";
      rows = [
        "decompress (fromBytes)",
        "mulBase",
        "mul",
        "mulAdd",
      ];
      cols = ["secp256k1"];
    };

    let curve = Curves.secp256k1;
    let k1 = 0xc6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5;
    let k2 = 0x4b688df40bcedbe641ddb16ff0a1842d9c67ea1c3bf63f3e0471baa664531d1a;
    let point = Jacobi.mulBase(k2, curve);
    let compressed = Jacobi.toBytes(point, true);

    func run(ri : Nat, _ : Nat) {
      switch (ri) {
        case (0) ignore Jacobi.fromBytes(compressed, curve);
        case (1) ignore Jacobi.toAffine(Jacobi.mulBase(k1, curve));
        case (2) ignore Jacobi.toAffine(Jacobi.mul(point, k1));
        case (_) ignore Jacobi.toAffine(Jacobi.mulAdd(Jacobi.base(curve), k1, point, k2));
      };
    };

    Bench.V1(schema, run);
  };
};
