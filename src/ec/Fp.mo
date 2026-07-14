/// Finite field element wrapper with modular arithmetic methods.
///
/// ```motoko name=import
/// import Fp "mo:bitcoin/ec/Fp";
/// ```

import Runtime "mo:core/Runtime";

import Field "Field";

module {
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
      Fp(Field.pow(value, (n + 1) / 4, n), n);
    };
  };
};
