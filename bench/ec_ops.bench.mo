import Bench "mo:bench-helper";

import Curves "../src/ec/Curves";
import Jacobi "../src/ec/Jacobi";

module {
  public func init() : Bench.V1 {
    let schema : Bench.Schema = {
      name = "EC operations on secp256k1";
      description = "Public key decompression, and scalar multiplication with a full-size and a short scalar. Decompression doesn't take a scalar and measures the same in both columns.";
      rows = [
        "decompress (fromBytes)",
        "mulBase",
        "mul",
        "mulAdd",
      ];
      cols = ["256-bit k", "57-bit k"];
    };

    let curve = Curves.secp256k1;
    let scalars = [
      [
        0xc6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5,
        0x4b688df40bcedbe641ddb16ff0a1842d9c67ea1c3bf63f3e0471baa664531d1a,
      ],
      [123456789123456789, 98765432198765432],
    ];
    let point = Jacobi.mulBase(0x4b688df40bcedbe641ddb16ff0a1842d9c67ea1c3bf63f3e0471baa664531d1a, curve);
    let compressed = Jacobi.toBytes(point, true);

    func run(ri : Nat, ci : Nat) {
      let k1 = scalars[ci][0];
      let k2 = scalars[ci][1];
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
