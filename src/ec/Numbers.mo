/// Number theory helpers used by elliptic curve routines.
///
/// ```motoko name=import
/// import Numbers "mo:bitcoin/ec/Numbers";
/// ```

import Array "mo:core/Array";
import List "mo:core/List";
import Runtime "mo:core/Runtime";

module {
  // Extended Euclidean Algorithm.
  /// Computes `(gcd, x, y)` such that `a*x + b*y = gcd`.
  ///
  /// Never traps. Returns `(a, 1, 0)` when `b == 0`.
  public func eea(a : Int, b : Int) : (Int, Int, Int) {
    if (b == 0) {
      return (a, 1, 0);
    };
    let (d, s, t) = eea(b, a % b);
    return (d, t, s - (a / b) * t);
  };

  // Convert given number to binary represented as an array of Bool in reverse
  // order.
  /// Converts `a` to reversed bit order (least significant bit first).
  ///
  /// Returns the empty array `[]` when `a == 0`. Never traps.
  public func toBinaryReversed(a : Nat) : [Bool] {
    let bitsBuffer = List.empty<Bool>();
    var number : Nat = a;

    while (number != 0) {
      bitsBuffer.add(number % 2 == 1);
      number /= 2;
    };

    bitsBuffer.toArray();
  };

  // Convert given number to binary represented as an array of Bool.
  /// Converts `a` to bit array (most significant bit first).
  ///
  /// Returns the empty array `[]` when `a == 0`. Never traps.
  public func toBinary(a : Nat) : [Bool] {
    let reversedBinary = toBinaryReversed(a);
    Array.tabulate<Bool>(
      reversedBinary.size(),
      func(i) {
        reversedBinary[reversedBinary.size() - i - 1];
      },
    );
  };

  // Compute the Non-adjacent form representiation of the given integer.
  /// Computes the non-adjacent form (NAF) digits of `n`.
  ///
  /// NAF is a signed binary representation where each digit is in
  /// `{-1, 0, 1}` and no two consecutive digits are non-zero. It is used
  /// to speed up scalar multiplication on elliptic curves by reducing the
  /// number of point additions.
  ///
  /// The result is least-significant-digit first. Returns the empty array
  /// `[]` when `n == 0`. Never traps.
  public func toNaf(n : Int) : [Int] {
    var input : Int = n;
    let output = List.empty<Int>();

    while (input != 0) {
      if (input % 2 != 0) {
        var nd : Int = input % 4;
        if (nd >= 2) {
          nd -= 4;
        };
        output.add(nd);
        input -= nd;
      } else {
        output.add(0);
      };
      input /= 2;
    };

    output.toArray();
  };

  /// Computes the width-`w` non-adjacent form (wNAF) digits of `n`.
  ///
  /// Every non-zero digit is odd with absolute value below `2^(w - 1)`, and
  /// any two non-zero digits are at least `w` positions apart, so on average
  /// only one digit in `w + 1` is non-zero. Scalar multiplication with a
  /// table of the odd multiples `P, 3P, ..., (2^(w - 1) - 1)P` then needs one
  /// point addition per non-zero digit. `toWnaf(n, 2)` equals `toNaf(n)`.
  ///
  /// The result is least-significant-digit first. Returns the empty array
  /// `[]` when `n == 0`. Traps if `w < 2`.
  public func toWnaf(n : Int, w : Nat) : [Int] {
    if (w < 2) Runtime.trap("toWnaf: width must be at least 2");
    let modulus : Int = 2 ** w;
    let half : Int = modulus / 2;
    var input : Int = n;
    let output = List.empty<Int>();

    while (input != 0) {
      if (input % 2 != 0) {
        var digit : Int = input % modulus;
        if (digit >= half) {
          digit -= modulus;
        } else if (digit < -half) {
          digit += modulus;
        };
        output.add(digit);
        input -= digit;
      } else {
        output.add(0);
      };
      input /= 2;
    };

    output.toArray();
  };
};
