/// Modular arithmetic primitives over natural numbers.
///
/// ```motoko name=import
/// import Field "mo:bitcoin/ec/Field";
/// ```

import Int "mo:core/Int";
import Nat "mo:core/Nat";

import Numbers "Numbers";

module {
  // Compute a ** -1 mod n.
  /// Computes modular inverse of `a` modulo `n`.
  ///
  /// Never traps. Returns `null` when `gcd(a, n) != 1` (in particular when
  /// `a == 0` or when `n` is composite and `a` shares a factor with `n`).
  public func inverse(a : Nat, n : Nat) : ?Nat {
    // Every value is congruent to 0 mod 1; return the canonical residue.
    if (n == 1) return ?0;
    // Iterative extended Euclid that tracks only the coefficient of `a`:
    // one bignum division per step. Invariant: t_i * a = r_i (mod n).
    var r0 : Nat = n;
    var r1 : Nat = a;
    var t0 : Int = 0;
    var t1 : Int = 1;
    while (r1 != 0) {
      let q = r0 / r1;
      let r2 : Nat = r0 - q * r1;
      r0 := r1;
      r1 := r2;
      let t2 = t0 - q * t1;
      t0 := t1;
      t1 := t2;
    };

    if (r0 != 1) {
      null;
    } else {
      ?Int.abs(if (t0 < 0) t0 + n else t0);
    };
  };

  // Compute a**b mod n.
  /// Computes `a^b mod n`.
  ///
  /// Returns `1` when `b == 0`, even if `n == 1`. Traps when `n == 0`
  /// (division by zero in the underlying `mul`).
  public func pow(a : Nat, b : Nat, n : Nat) : Nat {
    if (b == 0) {
      return 1;
    };

    let reversedBits = Numbers.toBinaryReversed(b);
    var result : Nat = 1;

    for (i in Nat.rangeByInclusive(reversedBits.size() - 1, 0, -1)) {
      result := mul(result, result, n);

      if (reversedBits[i]) {
        result := mul(result, a, n);
      };
    };
    return result;
  };

  // Compute a + b  mod n.
  /// Computes `(a + b) mod n`.
  ///
  /// Assumes `a < n` and `b < n`; never traps under that precondition.
  public func add(a : Nat, b : Nat, n : Nat) : Nat {
    let sum = a + b;

    if (sum < n) {
      sum;
    } else {
      sum - n;
    };
  };

  // Compute a * b  mod n.
  /// Computes `(a * b) mod n`.
  ///
  /// Traps on division by zero when `n == 0`.
  public func mul(a : Nat, b : Nat, n : Nat) : Nat {
    (a * b) % n;
  };

  // Compute a - b  mod n.
  /// Computes `(a - b) mod n`.
  ///
  /// Assumes `b < a + n`; never traps under that precondition.
  public func sub(a : Nat, b : Nat, n : Nat) : Nat {
    if (a >= b) {
      a - b;
    } else {
      (a + n) - b;
    };
  };

  // Compute -a  mod n.
  /// Computes additive inverse `(-a) mod n`.
  ///
  /// Assumes `a <= n`; traps on `Nat` underflow when `a > n`.
  public func neg(a : Nat, n : Nat) : Nat {
    if (a == 0) {
      0;
    } else {
      n - a;
    };
  };
};
