import Array "mo:core/Array";
import Bench "mo:bench-helper";

import Curves "../src/ec/Curves";
import Jacobi "../src/ec/Jacobi";
import Secp256r1 "../test/ec/Secp256r1";

module {
  public func init() : Bench.V1 {
    let schema : Bench.Schema = {
      name = "EC operations";
      description = "Public key decompression, and scalar multiplication with a full-size and a short scalar on secp256k1, and with a full-size scalar on secp256r1 (generic code paths). Decompression doesn't take a scalar and measures the same in both secp256k1 columns.";
      rows = [
        "decompress (fromBytes)",
        "mulBase",
        "mul",
        "mulAdd",
      ];
      cols = ["256-bit k", "57-bit k", "secp256r1, 256-bit k"];
    };

    let curves = [Curves.secp256k1, Curves.secp256k1, Secp256r1.curve];
    let scalars = [
      [
        0xc6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5,
        0x4b688df40bcedbe641ddb16ff0a1842d9c67ea1c3bf63f3e0471baa664531d1a,
      ],
      [123456789123456789, 98765432198765432],
      [
        0xc6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5,
        0x4b688df40bcedbe641ddb16ff0a1842d9c67ea1c3bf63f3e0471baa664531d1a,
      ],
    ];
    let points = curves.map(func(c : Curves.Curve) : Jacobi.Point = Jacobi.mulBase(0x4b688df40bcedbe641ddb16ff0a1842d9c67ea1c3bf63f3e0471baa664531d1a, c));
    let compressed = points.map(func(p : Jacobi.Point) : [Nat8] = Jacobi.toBytes(p, true));

    func run(ri : Nat, ci : Nat) {
      let k1 = scalars[ci][0];
      let k2 = scalars[ci][1];
      let curve = curves[ci];
      let point = points[ci];
      switch (ri) {
        case (0) ignore Jacobi.fromBytes(compressed[ci], curve);
        case (1) ignore Jacobi.toAffine(Jacobi.mulBase(k1, curve));
        case (2) ignore Jacobi.toAffine(Jacobi.mul(point, k1));
        case (_) ignore Jacobi.toAffine(Jacobi.mulAdd(Jacobi.base(curve), k1, point, k2));
      };
    };

    Bench.V1(schema, run);
  };
};
