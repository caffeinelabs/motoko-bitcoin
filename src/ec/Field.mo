/// Modular arithmetic primitives over natural numbers.
///
/// ```motoko name=import
/// import Field "mo:bitcoin/ec/Field";
/// ```

import Int "mo:core/Int";
import Nat "mo:core/Nat";
import Nat64 "mo:core/Nat64";
import VarArray "mo:core/VarArray";

module {
  // The field prime of secp256k1, 2^256 - 2^32 - 977, for which `mul` folds
  // instead of dividing.
  let SECP256K1_P : Nat = 0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f;
  let TWO_POW_512 : Nat = 0x100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000;

  // Reduces t < 2^512 modulo SECP256K1_P by folding the bits above 2^256
  // back in. With hi = t >> 256 and lo = t - hi * 2^256, the fold
  // lo + hi * (2^256 - p) equals t - hi * p, which takes one multiplication
  // and one subtraction instead of a shift, a subtraction, a multiplication
  // and an addition. Two folds bring t below 2^256 + 2^67 < 2p.
  func reduceSecp256k1(t : Nat) : Nat {
    let u : Nat = t - Nat.bitshiftRight(t, 256) * SECP256K1_P;
    let v : Nat = u - Nat.bitshiftRight(u, 256) * SECP256K1_P;
    if (v >= SECP256K1_P) v - SECP256K1_P else v;
  };

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

    let m = modulus(n);
    let base = a % n;
    // The exponent in 64-bit words, least significant first.
    var count = 0;
    var rest = b;
    while (rest != 0) {
      rest := Nat.bitshiftRight(rest, 64);
      count += 1;
    };
    let words = VarArray.repeat<Nat64>(0, count);
    rest := b;
    for (i in words.keys()) {
      words[i] := Nat64.fromIntWrap(rest);
      rest := Nat.bitshiftRight(rest, 64);
    };
    // Square and multiply from the top bit down.
    var result : Nat = 1;
    var i = count;
    while (i > 0) {
      i -= 1;
      let word = words[i];
      var bit : Nat64 = if (i + 1 == count) 1 << (63 - Nat64.bitcountLeadingZero(word)) else 1 << 63;
      while (bit != 0) {
        result := mulMod(result, result, m);
        if (word & bit != 0) result := mulMod(result, base, m);
        bit >>= 1;
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
    let t = a * b;
    if (n == SECP256K1_P and t < TWO_POW_512) reduceSecp256k1(t) else t % n;
  };

  /// A modulus `p` with the constants of Barrett reduction, for `mulMod`:
  /// `(p, mu, k, limit)` with the bit length k of p, mu = floor(2^(2k) / p)
  /// and limit = 2^(2k), below which Barrett reduction is exact. mu is 0
  /// for the secp256k1 prime, which `mulMod` reduces by folding. Build it
  /// with `modulus(p)`. (A tuple, because its fields are read faster than a
  /// record's.)
  public type Modulus = (Nat, Nat, Nat32, Nat);

  let SECP256K1_MODULUS : Modulus = (SECP256K1_P, 0, 256, TWO_POW_512);

  /// Precomputes the constants of `mulMod` for the modulus `p > 0`. Costs
  /// about one division; worth it for more than a few multiplications.
  public func modulus(p : Nat) : Modulus {
    if (p == SECP256K1_P) return SECP256K1_MODULUS;
    // Bit length of p, 64 bits at a time.
    var k : Nat32 = 0;
    var rest = p;
    while (rest >= 0x10000000000000000) {
      rest := Nat.bitshiftRight(rest, 64);
      k += 64;
    };
    k += 64 - Nat64.bitcountLeadingZero(Nat64.fromNat(rest)).toNat32();
    let limit = Nat.bitshiftLeft(1, 2 * k);
    (p, limit / p, k, limit);
  };

  /// Computes `(a * b) mod p` for the modulus `m = modulus(p)` with Barrett reduction instead of a
  /// division, or by folding for the secp256k1 prime.
  public func mulMod(a : Nat, b : Nat, m : Modulus) : Nat {
    let (p, mu, k, limit) = m;
    let t = a * b;
    if (t >= limit) return t % p;
    if (mu == 0) return reduceSecp256k1(t);
    // q is at most 2 below floor(t / p) (Handbook of Applied Cryptography,
    // 14.42), so at most two subtractions remain.
    let q = Nat.bitshiftRight(Nat.bitshiftRight(t, k - 1) * mu, k + 1);
    var r : Nat = t - q * p;
    while (r >= p) r -= p;
    r;
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
