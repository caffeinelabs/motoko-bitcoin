/// RIPEMD-160 hash implementation.
///
/// Provides a one-shot hash function and an incremental digest API.
/// RIPEMD-160 is used in Bitcoin as part of HASH160.
///
/// Import from the bitcoin package to use this module.
/// ```motoko name=import
/// import Ripemd160 "mo:bitcoin/Ripemd160";
/// ```

import Nat8 "mo:core/Nat8";
import Nat16 "mo:core/Nat16";
import Nat32 "mo:core/Nat32";
import Nat64 "mo:core/Nat64";
import VarArray "mo:core/VarArray";
import Prim "mo:prim";

module {
  /// Computes the RIPEMD-160 digest of `array`.
  ///
  /// Example:
  /// ```motoko include=import
  /// let digest = Ripemd160.hash([0x01, 0x02, 0x03]);
  /// ```
  ///
  /// Never traps. Always returns exactly 20 bytes.
  // Hash the given array and return finalized result.
  public func hash(array : [Nat8]) : [Nat8] {
    let digest = Digest();
    digest.write(array);
    digest.sum();
  };

  /// Incremental RIPEMD-160 digest state.
  ///
  /// Example:
  /// ```motoko include=import
  /// let d = Ripemd160.Digest();
  /// d.write([0x01, 0x02]);
  /// d.write([0x03]);
  /// let digest = d.sum();
  /// ```
  public class Digest() {
    // Persistent chaining state: 5 Nat32 words (h0..h4).
    // Stored inline in a [var Nat32] so per-block updates do not allocate.
    private let s : [var Nat32] = VarArray.repeat<Nat32>(0, 5);

    // Decoded message schedule for the block currently being assembled.
    // Each slot holds one little-endian 32-bit word; bytes are folded in
    // by writeByte and full 4-byte words are written wholesale by the
    // fast path in write(). Stored inline in a [var Nat32] so updates
    // inside the hot loop do not allocate.
    private let msg : [var Nat32] = VarArray.repeat<Nat32>(0, 16);

    // Number of bytes accumulated into the current (partial) block, 0..63.
    // Nat16 fits unboxed in mutable storage, avoiding heap traffic per byte.
    private var i_msg : Nat16 = 0;

    // Number of complete 64-byte blocks already absorbed.
    private var n_blocks : Nat64 = 0;

    // Flag to close Digest after call to sum()
    private var closed = false;

    private func initialize() {
      s[0] := 0x67452301;
      s[1] := 0xEFCDAB89;
      s[2] := 0x98BADCFE;
      s[3] := 0x10325476;
      s[4] := 0xC3D2E1F0;
      i_msg := 0;
      n_blocks := 0;
      // msg slots are overwritten before being read, so no clear needed here.
    };

    initialize();

    /// Resets the digest to its initial state.
    ///
    /// Never traps.
    public func reset() {
      initialize();
      closed := false;
    };

    private func rol(x : Nat32, r : Nat32) : Nat32 {
      (x << r) | (x >> (32 - r));
    };

    // Process the 16-word block currently held in msg, updating s.
    // The round structure is the standard RIPEMD-160 two-line schedule
    // with all 160 rounds inlined to avoid per-round tuple allocations.
    private func transform() {
      let w0 = msg[0];
      let w1 = msg[1];
      let w2 = msg[2];
      let w3 = msg[3];
      let w4 = msg[4];
      let w5 = msg[5];
      let w6 = msg[6];
      let w7 = msg[7];
      let w8 = msg[8];
      let w9 = msg[9];
      let w10 = msg[10];
      let w11 = msg[11];
      let w12 = msg[12];
      let w13 = msg[13];
      let w14 = msg[14];
      let w15 = msg[15];

      var a1 : Nat32 = s[0];
      var b1 : Nat32 = s[1];
      var c1 : Nat32 = s[2];
      var d1 : Nat32 = s[3];
      var e1 : Nat32 = s[4];
      var a2 : Nat32 = a1;
      var b2 : Nat32 = b1;
      var c2 : Nat32 = c1;
      var d2 : Nat32 = d1;
      var e2 : Nat32 = e1;

      // prettier-ignore
      do {
        // ---- Left line round 1: f1(b,c,d) = b^c^d, K = 0
        a1 := rol(a1 +% (b1 ^ c1 ^ d1) +% w0, 11) +% e1; c1 := rol(c1, 10);
        e1 := rol(e1 +% (a1 ^ b1 ^ c1) +% w1, 14) +% d1; b1 := rol(b1, 10);
        d1 := rol(d1 +% (e1 ^ a1 ^ b1) +% w2, 15) +% c1; a1 := rol(a1, 10);
        c1 := rol(c1 +% (d1 ^ e1 ^ a1) +% w3, 12) +% b1; e1 := rol(e1, 10);
        b1 := rol(b1 +% (c1 ^ d1 ^ e1) +% w4,  5) +% a1; d1 := rol(d1, 10);
        a1 := rol(a1 +% (b1 ^ c1 ^ d1) +% w5,  8) +% e1; c1 := rol(c1, 10);
        e1 := rol(e1 +% (a1 ^ b1 ^ c1) +% w6,  7) +% d1; b1 := rol(b1, 10);
        d1 := rol(d1 +% (e1 ^ a1 ^ b1) +% w7,  9) +% c1; a1 := rol(a1, 10);
        c1 := rol(c1 +% (d1 ^ e1 ^ a1) +% w8, 11) +% b1; e1 := rol(e1, 10);
        b1 := rol(b1 +% (c1 ^ d1 ^ e1) +% w9, 13) +% a1; d1 := rol(d1, 10);
        a1 := rol(a1 +% (b1 ^ c1 ^ d1) +% w10, 14) +% e1; c1 := rol(c1, 10);
        e1 := rol(e1 +% (a1 ^ b1 ^ c1) +% w11, 15) +% d1; b1 := rol(b1, 10);
        d1 := rol(d1 +% (e1 ^ a1 ^ b1) +% w12,  6) +% c1; a1 := rol(a1, 10);
        c1 := rol(c1 +% (d1 ^ e1 ^ a1) +% w13,  7) +% b1; e1 := rol(e1, 10);
        b1 := rol(b1 +% (c1 ^ d1 ^ e1) +% w14,  9) +% a1; d1 := rol(d1, 10);
        a1 := rol(a1 +% (b1 ^ c1 ^ d1) +% w15,  8) +% e1; c1 := rol(c1, 10);

        // ---- Left line round 2: f2(b,c,d) = (b & c) | (~b & d), K = 0x5A827999
        e1 := rol(e1 +% ((a1 & b1) | (^a1 & c1)) +% w7  +% 0x5A827999,  7) +% d1; b1 := rol(b1, 10);
        d1 := rol(d1 +% ((e1 & a1) | (^e1 & b1)) +% w4  +% 0x5A827999,  6) +% c1; a1 := rol(a1, 10);
        c1 := rol(c1 +% ((d1 & e1) | (^d1 & a1)) +% w13 +% 0x5A827999,  8) +% b1; e1 := rol(e1, 10);
        b1 := rol(b1 +% ((c1 & d1) | (^c1 & e1)) +% w1  +% 0x5A827999, 13) +% a1; d1 := rol(d1, 10);
        a1 := rol(a1 +% ((b1 & c1) | (^b1 & d1)) +% w10 +% 0x5A827999, 11) +% e1; c1 := rol(c1, 10);
        e1 := rol(e1 +% ((a1 & b1) | (^a1 & c1)) +% w6  +% 0x5A827999,  9) +% d1; b1 := rol(b1, 10);
        d1 := rol(d1 +% ((e1 & a1) | (^e1 & b1)) +% w15 +% 0x5A827999,  7) +% c1; a1 := rol(a1, 10);
        c1 := rol(c1 +% ((d1 & e1) | (^d1 & a1)) +% w3  +% 0x5A827999, 15) +% b1; e1 := rol(e1, 10);
        b1 := rol(b1 +% ((c1 & d1) | (^c1 & e1)) +% w12 +% 0x5A827999,  7) +% a1; d1 := rol(d1, 10);
        a1 := rol(a1 +% ((b1 & c1) | (^b1 & d1)) +% w0  +% 0x5A827999, 12) +% e1; c1 := rol(c1, 10);
        e1 := rol(e1 +% ((a1 & b1) | (^a1 & c1)) +% w9  +% 0x5A827999, 15) +% d1; b1 := rol(b1, 10);
        d1 := rol(d1 +% ((e1 & a1) | (^e1 & b1)) +% w5  +% 0x5A827999,  9) +% c1; a1 := rol(a1, 10);
        c1 := rol(c1 +% ((d1 & e1) | (^d1 & a1)) +% w2  +% 0x5A827999, 11) +% b1; e1 := rol(e1, 10);
        b1 := rol(b1 +% ((c1 & d1) | (^c1 & e1)) +% w14 +% 0x5A827999,  7) +% a1; d1 := rol(d1, 10);
        a1 := rol(a1 +% ((b1 & c1) | (^b1 & d1)) +% w11 +% 0x5A827999, 13) +% e1; c1 := rol(c1, 10);
        e1 := rol(e1 +% ((a1 & b1) | (^a1 & c1)) +% w8  +% 0x5A827999, 12) +% d1; b1 := rol(b1, 10);

        // ---- Left line round 3: f3(b,c,d) = (b | ~c) ^ d, K = 0x6ED9EBA1
        d1 := rol(d1 +% ((e1 | ^a1) ^ b1) +% w3  +% 0x6ED9EBA1, 11) +% c1; a1 := rol(a1, 10);
        c1 := rol(c1 +% ((d1 | ^e1) ^ a1) +% w10 +% 0x6ED9EBA1, 13) +% b1; e1 := rol(e1, 10);
        b1 := rol(b1 +% ((c1 | ^d1) ^ e1) +% w14 +% 0x6ED9EBA1,  6) +% a1; d1 := rol(d1, 10);
        a1 := rol(a1 +% ((b1 | ^c1) ^ d1) +% w4  +% 0x6ED9EBA1,  7) +% e1; c1 := rol(c1, 10);
        e1 := rol(e1 +% ((a1 | ^b1) ^ c1) +% w9  +% 0x6ED9EBA1, 14) +% d1; b1 := rol(b1, 10);
        d1 := rol(d1 +% ((e1 | ^a1) ^ b1) +% w15 +% 0x6ED9EBA1,  9) +% c1; a1 := rol(a1, 10);
        c1 := rol(c1 +% ((d1 | ^e1) ^ a1) +% w8  +% 0x6ED9EBA1, 13) +% b1; e1 := rol(e1, 10);
        b1 := rol(b1 +% ((c1 | ^d1) ^ e1) +% w1  +% 0x6ED9EBA1, 15) +% a1; d1 := rol(d1, 10);
        a1 := rol(a1 +% ((b1 | ^c1) ^ d1) +% w2  +% 0x6ED9EBA1, 14) +% e1; c1 := rol(c1, 10);
        e1 := rol(e1 +% ((a1 | ^b1) ^ c1) +% w7  +% 0x6ED9EBA1,  8) +% d1; b1 := rol(b1, 10);
        d1 := rol(d1 +% ((e1 | ^a1) ^ b1) +% w0  +% 0x6ED9EBA1, 13) +% c1; a1 := rol(a1, 10);
        c1 := rol(c1 +% ((d1 | ^e1) ^ a1) +% w6  +% 0x6ED9EBA1,  6) +% b1; e1 := rol(e1, 10);
        b1 := rol(b1 +% ((c1 | ^d1) ^ e1) +% w13 +% 0x6ED9EBA1,  5) +% a1; d1 := rol(d1, 10);
        a1 := rol(a1 +% ((b1 | ^c1) ^ d1) +% w11 +% 0x6ED9EBA1, 12) +% e1; c1 := rol(c1, 10);
        e1 := rol(e1 +% ((a1 | ^b1) ^ c1) +% w5  +% 0x6ED9EBA1,  7) +% d1; b1 := rol(b1, 10);
        d1 := rol(d1 +% ((e1 | ^a1) ^ b1) +% w12 +% 0x6ED9EBA1,  5) +% c1; a1 := rol(a1, 10);

        // ---- Left line round 4: f4(b,c,d) = (b & d) | (c & ~d), K = 0x8F1BBCDC
        c1 := rol(c1 +% ((d1 & a1) | (e1 & ^a1)) +% w1  +% 0x8F1BBCDC, 11) +% b1; e1 := rol(e1, 10);
        b1 := rol(b1 +% ((c1 & e1) | (d1 & ^e1)) +% w9  +% 0x8F1BBCDC, 12) +% a1; d1 := rol(d1, 10);
        a1 := rol(a1 +% ((b1 & d1) | (c1 & ^d1)) +% w11 +% 0x8F1BBCDC, 14) +% e1; c1 := rol(c1, 10);
        e1 := rol(e1 +% ((a1 & c1) | (b1 & ^c1)) +% w10 +% 0x8F1BBCDC, 15) +% d1; b1 := rol(b1, 10);
        d1 := rol(d1 +% ((e1 & b1) | (a1 & ^b1)) +% w0  +% 0x8F1BBCDC, 14) +% c1; a1 := rol(a1, 10);
        c1 := rol(c1 +% ((d1 & a1) | (e1 & ^a1)) +% w8  +% 0x8F1BBCDC, 15) +% b1; e1 := rol(e1, 10);
        b1 := rol(b1 +% ((c1 & e1) | (d1 & ^e1)) +% w12 +% 0x8F1BBCDC,  9) +% a1; d1 := rol(d1, 10);
        a1 := rol(a1 +% ((b1 & d1) | (c1 & ^d1)) +% w4  +% 0x8F1BBCDC,  8) +% e1; c1 := rol(c1, 10);
        e1 := rol(e1 +% ((a1 & c1) | (b1 & ^c1)) +% w13 +% 0x8F1BBCDC,  9) +% d1; b1 := rol(b1, 10);
        d1 := rol(d1 +% ((e1 & b1) | (a1 & ^b1)) +% w3  +% 0x8F1BBCDC, 14) +% c1; a1 := rol(a1, 10);
        c1 := rol(c1 +% ((d1 & a1) | (e1 & ^a1)) +% w7  +% 0x8F1BBCDC,  5) +% b1; e1 := rol(e1, 10);
        b1 := rol(b1 +% ((c1 & e1) | (d1 & ^e1)) +% w15 +% 0x8F1BBCDC,  6) +% a1; d1 := rol(d1, 10);
        a1 := rol(a1 +% ((b1 & d1) | (c1 & ^d1)) +% w14 +% 0x8F1BBCDC,  8) +% e1; c1 := rol(c1, 10);
        e1 := rol(e1 +% ((a1 & c1) | (b1 & ^c1)) +% w5  +% 0x8F1BBCDC,  6) +% d1; b1 := rol(b1, 10);
        d1 := rol(d1 +% ((e1 & b1) | (a1 & ^b1)) +% w6  +% 0x8F1BBCDC,  5) +% c1; a1 := rol(a1, 10);
        c1 := rol(c1 +% ((d1 & a1) | (e1 & ^a1)) +% w2  +% 0x8F1BBCDC, 12) +% b1; e1 := rol(e1, 10);

        // ---- Left line round 5: f5(b,c,d) = b ^ (c | ~d), K = 0xA953FD4E
        b1 := rol(b1 +% (c1 ^ (d1 | ^e1)) +% w4  +% 0xA953FD4E,  9) +% a1; d1 := rol(d1, 10);
        a1 := rol(a1 +% (b1 ^ (c1 | ^d1)) +% w0  +% 0xA953FD4E, 15) +% e1; c1 := rol(c1, 10);
        e1 := rol(e1 +% (a1 ^ (b1 | ^c1)) +% w5  +% 0xA953FD4E,  5) +% d1; b1 := rol(b1, 10);
        d1 := rol(d1 +% (e1 ^ (a1 | ^b1)) +% w9  +% 0xA953FD4E, 11) +% c1; a1 := rol(a1, 10);
        c1 := rol(c1 +% (d1 ^ (e1 | ^a1)) +% w7  +% 0xA953FD4E,  6) +% b1; e1 := rol(e1, 10);
        b1 := rol(b1 +% (c1 ^ (d1 | ^e1)) +% w12 +% 0xA953FD4E,  8) +% a1; d1 := rol(d1, 10);
        a1 := rol(a1 +% (b1 ^ (c1 | ^d1)) +% w2  +% 0xA953FD4E, 13) +% e1; c1 := rol(c1, 10);
        e1 := rol(e1 +% (a1 ^ (b1 | ^c1)) +% w10 +% 0xA953FD4E, 12) +% d1; b1 := rol(b1, 10);
        d1 := rol(d1 +% (e1 ^ (a1 | ^b1)) +% w14 +% 0xA953FD4E,  5) +% c1; a1 := rol(a1, 10);
        c1 := rol(c1 +% (d1 ^ (e1 | ^a1)) +% w1  +% 0xA953FD4E, 12) +% b1; e1 := rol(e1, 10);
        b1 := rol(b1 +% (c1 ^ (d1 | ^e1)) +% w3  +% 0xA953FD4E, 13) +% a1; d1 := rol(d1, 10);
        a1 := rol(a1 +% (b1 ^ (c1 | ^d1)) +% w8  +% 0xA953FD4E, 14) +% e1; c1 := rol(c1, 10);
        e1 := rol(e1 +% (a1 ^ (b1 | ^c1)) +% w11 +% 0xA953FD4E, 11) +% d1; b1 := rol(b1, 10);
        d1 := rol(d1 +% (e1 ^ (a1 | ^b1)) +% w6  +% 0xA953FD4E,  8) +% c1; a1 := rol(a1, 10);
        c1 := rol(c1 +% (d1 ^ (e1 | ^a1)) +% w15 +% 0xA953FD4E,  5) +% b1; e1 := rol(e1, 10);
        b1 := rol(b1 +% (c1 ^ (d1 | ^e1)) +% w13 +% 0xA953FD4E,  6) +% a1; d1 := rol(d1, 10);

        // ---- Right line round 1: f5, K = 0x50A28BE6
        a2 := rol(a2 +% (b2 ^ (c2 | ^d2)) +% w5  +% 0x50A28BE6,  8) +% e2; c2 := rol(c2, 10);
        e2 := rol(e2 +% (a2 ^ (b2 | ^c2)) +% w14 +% 0x50A28BE6,  9) +% d2; b2 := rol(b2, 10);
        d2 := rol(d2 +% (e2 ^ (a2 | ^b2)) +% w7  +% 0x50A28BE6,  9) +% c2; a2 := rol(a2, 10);
        c2 := rol(c2 +% (d2 ^ (e2 | ^a2)) +% w0  +% 0x50A28BE6, 11) +% b2; e2 := rol(e2, 10);
        b2 := rol(b2 +% (c2 ^ (d2 | ^e2)) +% w9  +% 0x50A28BE6, 13) +% a2; d2 := rol(d2, 10);
        a2 := rol(a2 +% (b2 ^ (c2 | ^d2)) +% w2  +% 0x50A28BE6, 15) +% e2; c2 := rol(c2, 10);
        e2 := rol(e2 +% (a2 ^ (b2 | ^c2)) +% w11 +% 0x50A28BE6, 15) +% d2; b2 := rol(b2, 10);
        d2 := rol(d2 +% (e2 ^ (a2 | ^b2)) +% w4  +% 0x50A28BE6,  5) +% c2; a2 := rol(a2, 10);
        c2 := rol(c2 +% (d2 ^ (e2 | ^a2)) +% w13 +% 0x50A28BE6,  7) +% b2; e2 := rol(e2, 10);
        b2 := rol(b2 +% (c2 ^ (d2 | ^e2)) +% w6  +% 0x50A28BE6,  7) +% a2; d2 := rol(d2, 10);
        a2 := rol(a2 +% (b2 ^ (c2 | ^d2)) +% w15 +% 0x50A28BE6,  8) +% e2; c2 := rol(c2, 10);
        e2 := rol(e2 +% (a2 ^ (b2 | ^c2)) +% w8  +% 0x50A28BE6, 11) +% d2; b2 := rol(b2, 10);
        d2 := rol(d2 +% (e2 ^ (a2 | ^b2)) +% w1  +% 0x50A28BE6, 14) +% c2; a2 := rol(a2, 10);
        c2 := rol(c2 +% (d2 ^ (e2 | ^a2)) +% w10 +% 0x50A28BE6, 14) +% b2; e2 := rol(e2, 10);
        b2 := rol(b2 +% (c2 ^ (d2 | ^e2)) +% w3  +% 0x50A28BE6, 12) +% a2; d2 := rol(d2, 10);
        a2 := rol(a2 +% (b2 ^ (c2 | ^d2)) +% w12 +% 0x50A28BE6,  6) +% e2; c2 := rol(c2, 10);

        // ---- Right line round 2: f4, K = 0x5C4DD124
        e2 := rol(e2 +% ((a2 & c2) | (b2 & ^c2)) +% w6  +% 0x5C4DD124,  9) +% d2; b2 := rol(b2, 10);
        d2 := rol(d2 +% ((e2 & b2) | (a2 & ^b2)) +% w11 +% 0x5C4DD124, 13) +% c2; a2 := rol(a2, 10);
        c2 := rol(c2 +% ((d2 & a2) | (e2 & ^a2)) +% w3  +% 0x5C4DD124, 15) +% b2; e2 := rol(e2, 10);
        b2 := rol(b2 +% ((c2 & e2) | (d2 & ^e2)) +% w7  +% 0x5C4DD124,  7) +% a2; d2 := rol(d2, 10);
        a2 := rol(a2 +% ((b2 & d2) | (c2 & ^d2)) +% w0  +% 0x5C4DD124, 12) +% e2; c2 := rol(c2, 10);
        e2 := rol(e2 +% ((a2 & c2) | (b2 & ^c2)) +% w13 +% 0x5C4DD124,  8) +% d2; b2 := rol(b2, 10);
        d2 := rol(d2 +% ((e2 & b2) | (a2 & ^b2)) +% w5  +% 0x5C4DD124,  9) +% c2; a2 := rol(a2, 10);
        c2 := rol(c2 +% ((d2 & a2) | (e2 & ^a2)) +% w10 +% 0x5C4DD124, 11) +% b2; e2 := rol(e2, 10);
        b2 := rol(b2 +% ((c2 & e2) | (d2 & ^e2)) +% w14 +% 0x5C4DD124,  7) +% a2; d2 := rol(d2, 10);
        a2 := rol(a2 +% ((b2 & d2) | (c2 & ^d2)) +% w15 +% 0x5C4DD124,  7) +% e2; c2 := rol(c2, 10);
        e2 := rol(e2 +% ((a2 & c2) | (b2 & ^c2)) +% w8  +% 0x5C4DD124, 12) +% d2; b2 := rol(b2, 10);
        d2 := rol(d2 +% ((e2 & b2) | (a2 & ^b2)) +% w12 +% 0x5C4DD124,  7) +% c2; a2 := rol(a2, 10);
        c2 := rol(c2 +% ((d2 & a2) | (e2 & ^a2)) +% w4  +% 0x5C4DD124,  6) +% b2; e2 := rol(e2, 10);
        b2 := rol(b2 +% ((c2 & e2) | (d2 & ^e2)) +% w9  +% 0x5C4DD124, 15) +% a2; d2 := rol(d2, 10);
        a2 := rol(a2 +% ((b2 & d2) | (c2 & ^d2)) +% w1  +% 0x5C4DD124, 13) +% e2; c2 := rol(c2, 10);
        e2 := rol(e2 +% ((a2 & c2) | (b2 & ^c2)) +% w2  +% 0x5C4DD124, 11) +% d2; b2 := rol(b2, 10);

        // ---- Right line round 3: f3, K = 0x6D703EF3
        d2 := rol(d2 +% ((e2 | ^a2) ^ b2) +% w15 +% 0x6D703EF3,  9) +% c2; a2 := rol(a2, 10);
        c2 := rol(c2 +% ((d2 | ^e2) ^ a2) +% w5  +% 0x6D703EF3,  7) +% b2; e2 := rol(e2, 10);
        b2 := rol(b2 +% ((c2 | ^d2) ^ e2) +% w1  +% 0x6D703EF3, 15) +% a2; d2 := rol(d2, 10);
        a2 := rol(a2 +% ((b2 | ^c2) ^ d2) +% w3  +% 0x6D703EF3, 11) +% e2; c2 := rol(c2, 10);
        e2 := rol(e2 +% ((a2 | ^b2) ^ c2) +% w7  +% 0x6D703EF3,  8) +% d2; b2 := rol(b2, 10);
        d2 := rol(d2 +% ((e2 | ^a2) ^ b2) +% w14 +% 0x6D703EF3,  6) +% c2; a2 := rol(a2, 10);
        c2 := rol(c2 +% ((d2 | ^e2) ^ a2) +% w6  +% 0x6D703EF3,  6) +% b2; e2 := rol(e2, 10);
        b2 := rol(b2 +% ((c2 | ^d2) ^ e2) +% w9  +% 0x6D703EF3, 14) +% a2; d2 := rol(d2, 10);
        a2 := rol(a2 +% ((b2 | ^c2) ^ d2) +% w11 +% 0x6D703EF3, 12) +% e2; c2 := rol(c2, 10);
        e2 := rol(e2 +% ((a2 | ^b2) ^ c2) +% w8  +% 0x6D703EF3, 13) +% d2; b2 := rol(b2, 10);
        d2 := rol(d2 +% ((e2 | ^a2) ^ b2) +% w12 +% 0x6D703EF3,  5) +% c2; a2 := rol(a2, 10);
        c2 := rol(c2 +% ((d2 | ^e2) ^ a2) +% w2  +% 0x6D703EF3, 14) +% b2; e2 := rol(e2, 10);
        b2 := rol(b2 +% ((c2 | ^d2) ^ e2) +% w10 +% 0x6D703EF3, 13) +% a2; d2 := rol(d2, 10);
        a2 := rol(a2 +% ((b2 | ^c2) ^ d2) +% w0  +% 0x6D703EF3, 13) +% e2; c2 := rol(c2, 10);
        e2 := rol(e2 +% ((a2 | ^b2) ^ c2) +% w4  +% 0x6D703EF3,  7) +% d2; b2 := rol(b2, 10);
        d2 := rol(d2 +% ((e2 | ^a2) ^ b2) +% w13 +% 0x6D703EF3,  5) +% c2; a2 := rol(a2, 10);

        // ---- Right line round 4: f2, K = 0x7A6D76E9
        c2 := rol(c2 +% ((d2 & e2) | (^d2 & a2)) +% w8  +% 0x7A6D76E9, 15) +% b2; e2 := rol(e2, 10);
        b2 := rol(b2 +% ((c2 & d2) | (^c2 & e2)) +% w6  +% 0x7A6D76E9,  5) +% a2; d2 := rol(d2, 10);
        a2 := rol(a2 +% ((b2 & c2) | (^b2 & d2)) +% w4  +% 0x7A6D76E9,  8) +% e2; c2 := rol(c2, 10);
        e2 := rol(e2 +% ((a2 & b2) | (^a2 & c2)) +% w1  +% 0x7A6D76E9, 11) +% d2; b2 := rol(b2, 10);
        d2 := rol(d2 +% ((e2 & a2) | (^e2 & b2)) +% w3  +% 0x7A6D76E9, 14) +% c2; a2 := rol(a2, 10);
        c2 := rol(c2 +% ((d2 & e2) | (^d2 & a2)) +% w11 +% 0x7A6D76E9, 14) +% b2; e2 := rol(e2, 10);
        b2 := rol(b2 +% ((c2 & d2) | (^c2 & e2)) +% w15 +% 0x7A6D76E9,  6) +% a2; d2 := rol(d2, 10);
        a2 := rol(a2 +% ((b2 & c2) | (^b2 & d2)) +% w0  +% 0x7A6D76E9, 14) +% e2; c2 := rol(c2, 10);
        e2 := rol(e2 +% ((a2 & b2) | (^a2 & c2)) +% w5  +% 0x7A6D76E9,  6) +% d2; b2 := rol(b2, 10);
        d2 := rol(d2 +% ((e2 & a2) | (^e2 & b2)) +% w12 +% 0x7A6D76E9,  9) +% c2; a2 := rol(a2, 10);
        c2 := rol(c2 +% ((d2 & e2) | (^d2 & a2)) +% w2  +% 0x7A6D76E9, 12) +% b2; e2 := rol(e2, 10);
        b2 := rol(b2 +% ((c2 & d2) | (^c2 & e2)) +% w13 +% 0x7A6D76E9,  9) +% a2; d2 := rol(d2, 10);
        a2 := rol(a2 +% ((b2 & c2) | (^b2 & d2)) +% w9  +% 0x7A6D76E9, 12) +% e2; c2 := rol(c2, 10);
        e2 := rol(e2 +% ((a2 & b2) | (^a2 & c2)) +% w7  +% 0x7A6D76E9,  5) +% d2; b2 := rol(b2, 10);
        d2 := rol(d2 +% ((e2 & a2) | (^e2 & b2)) +% w10 +% 0x7A6D76E9, 15) +% c2; a2 := rol(a2, 10);
        c2 := rol(c2 +% ((d2 & e2) | (^d2 & a2)) +% w14 +% 0x7A6D76E9,  8) +% b2; e2 := rol(e2, 10);

        // ---- Right line round 5: f1, K = 0
        b2 := rol(b2 +% (c2 ^ d2 ^ e2) +% w12,  8) +% a2; d2 := rol(d2, 10);
        a2 := rol(a2 +% (b2 ^ c2 ^ d2) +% w15,  5) +% e2; c2 := rol(c2, 10);
        e2 := rol(e2 +% (a2 ^ b2 ^ c2) +% w10, 12) +% d2; b2 := rol(b2, 10);
        d2 := rol(d2 +% (e2 ^ a2 ^ b2) +% w4,   9) +% c2; a2 := rol(a2, 10);
        c2 := rol(c2 +% (d2 ^ e2 ^ a2) +% w1,  12) +% b2; e2 := rol(e2, 10);
        b2 := rol(b2 +% (c2 ^ d2 ^ e2) +% w5,   5) +% a2; d2 := rol(d2, 10);
        a2 := rol(a2 +% (b2 ^ c2 ^ d2) +% w8,  14) +% e2; c2 := rol(c2, 10);
        e2 := rol(e2 +% (a2 ^ b2 ^ c2) +% w7,   6) +% d2; b2 := rol(b2, 10);
        d2 := rol(d2 +% (e2 ^ a2 ^ b2) +% w6,   8) +% c2; a2 := rol(a2, 10);
        c2 := rol(c2 +% (d2 ^ e2 ^ a2) +% w2,  13) +% b2; e2 := rol(e2, 10);
        b2 := rol(b2 +% (c2 ^ d2 ^ e2) +% w13,  6) +% a2; d2 := rol(d2, 10);
        a2 := rol(a2 +% (b2 ^ c2 ^ d2) +% w14,  5) +% e2; c2 := rol(c2, 10);
        e2 := rol(e2 +% (a2 ^ b2 ^ c2) +% w0,  15) +% d2; b2 := rol(b2, 10);
        d2 := rol(d2 +% (e2 ^ a2 ^ b2) +% w3,  13) +% c2; a2 := rol(a2, 10);
        c2 := rol(c2 +% (d2 ^ e2 ^ a2) +% w9,  11) +% b2; e2 := rol(e2, 10);
        b2 := rol(b2 +% (c2 ^ d2 ^ e2) +% w11, 11) +% a2; d2 := rol(d2, 10);
      };

      // Combine the two lines back into the chaining state.
      let t : Nat32 = s[0];
      s[0] := s[1] +% c1 +% d2;
      s[1] := s[2] +% d1 +% e2;
      s[2] := s[3] +% e1 +% a2;
      s[3] := s[4] +% a1 +% b2;
      s[4] := t +% b1 +% c2;
    };

    // Append a single byte to the current block, processing the block when
    // it becomes full. The byte is folded into msg[i_msg >> 2] at the
    // little-endian position implied by (i_msg & 3).
    private func writeByte(b : Nat8) {
      let pos = i_msg;
      let wi = Nat16.toNat(pos >> 2);
      let lane = pos & 0x3;
      let v : Nat32 = b.toNat16().toNat32() << (lane << 3).toNat32();
      if (lane == 0) {
        // First byte of a fresh word: overwrite (the slot may carry stale
        // data from an earlier block, since we never explicitly clear msg).
        msg[wi] := v;
      } else {
        msg[wi] := msg[wi] | v;
      };
      let next = pos +% 1;
      if (next == 64) {
        transform();
        n_blocks +%= 1;
        i_msg := 0;
      } else {
        i_msg := next;
      };
    };

    /// Adds `data` to the digest state.
    ///
    /// Accepts an array of any length, including the empty array. Does not trap
    /// on any input, but traps if called after `sum()` has locked the Digest
    /// (call `reset()` first to reuse it).
    public func write(data : [Nat8]) {
      // Don't allow writes if Digest is closed, i.e. after sum()
      assert (not closed);

      let n = data.size();
      if (n == 0) return;
      var i = 0;

      // 1) If a partial block is in progress, fill it byte by byte.
      while (i_msg != 0 and i < n) {
        writeByte(data[i]);
        i += 1;
      };

      // 2) Fast path: process any number of full 64-byte blocks directly,
      //    decoding 16 little-endian words inline into msg per block.
      // prettier-ignore
      while (i + 64 <= n) {
        msg[0]  := data[i].toNat16().toNat32()    | (data[i+1].toNat16().toNat32()  << 8) | (data[i+2].toNat16().toNat32()  << 16) | (data[i+3].toNat16().toNat32()  << 24);
        msg[1]  := data[i+4].toNat16().toNat32()  | (data[i+5].toNat16().toNat32()  << 8) | (data[i+6].toNat16().toNat32()  << 16) | (data[i+7].toNat16().toNat32()  << 24);
        msg[2]  := data[i+8].toNat16().toNat32()  | (data[i+9].toNat16().toNat32()  << 8) | (data[i+10].toNat16().toNat32() << 16) | (data[i+11].toNat16().toNat32() << 24);
        msg[3]  := data[i+12].toNat16().toNat32() | (data[i+13].toNat16().toNat32() << 8) | (data[i+14].toNat16().toNat32() << 16) | (data[i+15].toNat16().toNat32() << 24);
        msg[4]  := data[i+16].toNat16().toNat32() | (data[i+17].toNat16().toNat32() << 8) | (data[i+18].toNat16().toNat32() << 16) | (data[i+19].toNat16().toNat32() << 24);
        msg[5]  := data[i+20].toNat16().toNat32() | (data[i+21].toNat16().toNat32() << 8) | (data[i+22].toNat16().toNat32() << 16) | (data[i+23].toNat16().toNat32() << 24);
        msg[6]  := data[i+24].toNat16().toNat32() | (data[i+25].toNat16().toNat32() << 8) | (data[i+26].toNat16().toNat32() << 16) | (data[i+27].toNat16().toNat32() << 24);
        msg[7]  := data[i+28].toNat16().toNat32() | (data[i+29].toNat16().toNat32() << 8) | (data[i+30].toNat16().toNat32() << 16) | (data[i+31].toNat16().toNat32() << 24);
        msg[8]  := data[i+32].toNat16().toNat32() | (data[i+33].toNat16().toNat32() << 8) | (data[i+34].toNat16().toNat32() << 16) | (data[i+35].toNat16().toNat32() << 24);
        msg[9]  := data[i+36].toNat16().toNat32() | (data[i+37].toNat16().toNat32() << 8) | (data[i+38].toNat16().toNat32() << 16) | (data[i+39].toNat16().toNat32() << 24);
        msg[10] := data[i+40].toNat16().toNat32() | (data[i+41].toNat16().toNat32() << 8) | (data[i+42].toNat16().toNat32() << 16) | (data[i+43].toNat16().toNat32() << 24);
        msg[11] := data[i+44].toNat16().toNat32() | (data[i+45].toNat16().toNat32() << 8) | (data[i+46].toNat16().toNat32() << 16) | (data[i+47].toNat16().toNat32() << 24);
        msg[12] := data[i+48].toNat16().toNat32() | (data[i+49].toNat16().toNat32() << 8) | (data[i+50].toNat16().toNat32() << 16) | (data[i+51].toNat16().toNat32() << 24);
        msg[13] := data[i+52].toNat16().toNat32() | (data[i+53].toNat16().toNat32() << 8) | (data[i+54].toNat16().toNat32() << 16) | (data[i+55].toNat16().toNat32() << 24);
        msg[14] := data[i+56].toNat16().toNat32() | (data[i+57].toNat16().toNat32() << 8) | (data[i+58].toNat16().toNat32() << 16) | (data[i+59].toNat16().toNat32() << 24);
        msg[15] := data[i+60].toNat16().toNat32() | (data[i+61].toNat16().toNat32() << 8) | (data[i+62].toNat16().toNat32() << 16) | (data[i+63].toNat16().toNat32() << 24);
        transform();
        n_blocks +%= 1;
        i += 64;
      };

      // 3) Tail: copy remaining bytes one at a time into the partial block.
      while (i < n) {
        writeByte(data[i]);
        i += 1;
      };
    };

    /// Finalize the digest and return the 20-byte RIPEMD-160 hash.
    ///
    /// NOTE: sum() is consuming and locks the Digest.
    /// Calling sum() a second time or calling write() after sum() will trap.
    /// You have to call reset() before you can re-use a Digest for another message.
    public func sum() : [Nat8] {
      // Prevent sum() from being called twice.
      assert (not closed);

      // Close Digest for further writes.
      closed := true;

      // Total message length in bits, captured before padding is appended.
      let bitlen : Nat64 = ((n_blocks << 6) +% i_msg.toNat32().toNat64()) << 3;

      // Standard MD-style padding: 0x80 byte, then zeros until 56 bytes
      // remain in the current block, then 8 bytes of bit length (LE).
      writeByte(0x80);
      while (i_msg != 56) {
        writeByte(0);
      };
      writeByte(Nat8.fromIntWrap(Nat64.toNat(bitlen)));
      writeByte(Nat8.fromIntWrap(Nat64.toNat(bitlen >> 8)));
      writeByte(Nat8.fromIntWrap(Nat64.toNat(bitlen >> 16)));
      writeByte(Nat8.fromIntWrap(Nat64.toNat(bitlen >> 24)));
      writeByte(Nat8.fromIntWrap(Nat64.toNat(bitlen >> 32)));
      writeByte(Nat8.fromIntWrap(Nat64.toNat(bitlen >> 40)));
      writeByte(Nat8.fromIntWrap(Nat64.toNat(bitlen >> 48)));
      writeByte(Nat8.fromIntWrap(Nat64.toNat(bitlen >> 56)));
      // The 8th length byte fills the block, triggering transform().

      // Serialize the 5 chaining words as 20 little-endian bytes.
      let (b3, b2, b1, b0) = Prim.explodeNat32(s[0]);
      let (b7, b6, b5, b4) = Prim.explodeNat32(s[1]);
      let (b11, b10, b9, b8) = Prim.explodeNat32(s[2]);
      let (b15, b14, b13, b12) = Prim.explodeNat32(s[3]);
      let (b19, b18, b17, b16) = Prim.explodeNat32(s[4]);

      // prettier-ignore
      [
        b0,  b1,  b2,  b3,
        b4,  b5,  b6,  b7,
        b8,  b9,  b10, b11,
        b12, b13, b14, b15,
        b16, b17, b18, b19,
      ];
    };
  };
};
