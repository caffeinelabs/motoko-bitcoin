/// Finite field element wrapper with modular arithmetic methods.
///
/// ```motoko name=import
/// import Fp "mo:bitcoin/ec/Fp";
/// ```

import Nat "mo:core/Nat";
import Runtime "mo:core/Runtime";

import Field "Field";

module {
  // The field prime of secp256k1, 2^256 - 2^32 - 977.
  let SECP256K1_P : Nat = 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f;

  // a^((p + 1) / 4) mod p for the secp256k1 prime and a < p, with an
  // addition chain of 253 squarings and 13 multiplications (Field.mul folds
  // instead of dividing for this p).
  func sqrtSecp256k1(a : Nat) : Nat {
    func m(x : Nat, y : Nat) : Nat = Field.mul(x, y, SECP256K1_P);
    // x^(2^n)
    func sqrN(x : Nat, n : Nat) : Nat {
      var r = x;
      for (_ in Nat.range(0, n)) {
        r := Field.mul(r, r, SECP256K1_P);
      };
      r;
    };
    // xK = a^(2^K - 1)
    let x2 = m(sqrN(a, 1), a);
    let x3 = m(sqrN(x2, 1), a);
    let x6 = m(sqrN(x3, 3), x3);
    let x9 = m(sqrN(x6, 3), x3);
    let x11 = m(sqrN(x9, 2), x2);
    let x22 = m(sqrN(x11, 11), x11);
    let x44 = m(sqrN(x22, 22), x22);
    let x88 = m(sqrN(x44, 44), x44);
    let x176 = m(sqrN(x88, 88), x88);
    let x220 = m(sqrN(x176, 44), x44);
    let x223 = m(sqrN(x220, 3), x3);
    let t = m(sqrN(m(sqrN(x223, 23), x22), 6), x2);
    sqrN(t, 2);
  };

  // Arithmetic computations modulo n over the given _value.
  /// Field element over modulus `n`.
  ///
  /// Constructor arguments:
  /// - `_value` — the integer value (will be reduced modulo `n`).
  /// - `n` — the modulus. For a true prime field this should be prime;
  ///   methods like `inverse` and `sqrt` assume primality.
  ///
  /// Operations on `Fp` instances with different moduli produce undefined
  /// results — callers must keep moduli consistent.
  public class Fp(_value : Nat, n : Nat) : Fp {
    /// Canonical value reduced modulo `n`.
    public let value : Nat = _value % n;

    // Compute value ** -1 mod n. The inverse does not exist if _value and n are
    // not relatively prime.
    /// Returns multiplicative inverse modulo `n`.
    ///
    /// Traps with `"unreachable"` when `value` is not coprime to `n` (in
    /// particular when `value == 0`, or when `n` is composite and `value`
    /// shares a factor with it).
    public func inverse() : Fp {
      let inverse : ?Nat = Field.inverse(value, n);
      switch inverse {
        case (null) {
          Runtime.trap("unreachable");
        };
        case (?inverse) {
          return Fp(inverse, n);
        };
      };
    };

    // Compute value + other mod n.
    /// Adds two field elements.
    public func add(other : Fp) : Fp = Fp(Field.add(value, other.value, n), n);

    // Compute value * other mod n.
    /// Multiplies two field elements.
    public func mul(other : Fp) : Fp = Fp(Field.mul(value, other.value, n), n);

    // Compute value * 2 mod n.
    /// Squares this field element.
    public func sqr() : Fp = Fp(Field.mul(value, value, n), n);

    // Compute value - other mod n.
    /// Subtracts another field element.
    public func sub(other : Fp) : Fp = Fp(Field.sub(value, other.value, n), n);

    // Compute -value mod n.
    /// Negates this field element.
    public func neg() : Fp = Fp(Field.neg(value, n), n);

    // Check equality with the given Fp object.
    /// Checks value equality.
    public func isEqual(other : Fp) : Bool = other.value == value;

    // Compute value ** other mod n.
    /// Raises this element to `exponent` modulo `n`.
    public func pow(exponent : Nat) : Fp = Fp(Field.pow(value, exponent, n), n);

    /// Computes a square root of `value` modulo `n` for the special case
    /// where `n` is a prime and `n ≡ 3 (mod 4)`.
    ///
    /// In this case, the square root (when it exists) can be computed as
    /// `value^((n + 1) / 4) mod n`, which is a shortcut of the
    /// Tonelli–Shanks algorithm.
    ///
    /// Note:
    /// - This function does not check whether a square root exists.
    /// - The returned value is only valid if `value` is a quadratic residue mod `n`.
    /// - Callers should verify the result by checking `result.sqr().isEqual(value)`,
    ///   where `result` is the returned Fp value and `value` is the Fp instance on
    ///   which sqrt() was called.
    ///
    /// Never traps.
    public func sqrt() : Fp {
      if (n == SECP256K1_P) {
        Fp(sqrtSecp256k1(value), n);
      } else {
        Fp(Field.pow(value, (n + 1) / 4, n), n);
      };
    };
  };
};
