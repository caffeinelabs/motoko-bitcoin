/// Base58 encoding and decoding for binary data.
///
/// Base58 is a binary-to-text encoding used in Bitcoin to encode addresses
/// and other data. It uses 58 alphanumeric characters, excluding visually
/// ambiguous characters such as `0`, `I`, `O`, and `l`.
///
/// Import from the bitcoin package to use this module.
/// ```motoko name=import
/// import Base58 "mo:bitcoin/Base58";
/// ```

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Nat16 "mo:core/Nat16";
import Nat32 "mo:core/Nat32";
import Nat64 "mo:core/Nat64";
import Nat8 "mo:core/Nat8";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";
import VarArray "mo:core/VarArray";

module {
  // All alphanumeric characters except for "0", "I", "O", and "l".
  // prettier-ignore
  private let base58Alphabet : [Nat8] = [
    49, 50, 51, 52, 53, 54, 55, 56, 57, 65, 66, 67, 68, 69, 70, 71,
    72, 74, 75, 76, 77, 78, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90,
    97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 109, 110, 111, 112, 113, 114,
    115, 116, 117, 118, 119, 120, 121, 122
  ];

  // prettier-ignore
  private let mapBase58 : [Nat] = [
    255,255,255,255,255,255,255,255, 255,255,255,255,255,255,255,255,
    255,255,255,255,255,255,255,255, 255,255,255,255,255,255,255,255,
    255,255,255,255,255,255,255,255, 255,255,255,255,255,255,255,255, 255, 0,
    1, 2, 3, 4, 5, 6, 7, 8,255,255,255,255,255,255, 255, 9,10,11,12,13,14,15,
    16,255,17,18,19,20,21,255, 22,23,24,25,26,27,28,29,
    30,31,32,255,255,255,255,255, 255,33,34,35,36,37,38,39,
    40,41,42,43,255,44,45,46, 47,48,49,50,51,52,53,54,
    55,56,57,255,255,255,255,255, 255,255,255,255,255,255,255,255,
    255,255,255,255,255,255,255,255, 255,255,255,255,255,255,255,255,
    255,255,255,255,255,255,255,255, 255,255,255,255,255,255,255,255,
    255,255,255,255,255,255,255,255, 255,255,255,255,255,255,255,255,
    255,255,255,255,255,255,255,255, 255,255,255,255,255,255,255,255,
    255,255,255,255,255,255,255,255, 255,255,255,255,255,255,255,255,
    255,255,255,255,255,255,255,255, 255,255,255,255,255,255,255,255,
    255,255,255,255,255,255,255,255, 255,255,255,255,255,255,255,255,
    255,255,255,255,255,255,255,255,
  ];

  func arrayToText(arr : [Nat8]) : Text {
    switch (arr.toBlob().decodeUtf8()) {
      case (?t) t;
      case null Runtime.trap("unreachable");
    };
  };

  /// Returns `true` if `input` consists entirely of characters from the
  /// Base58 alphabet (`123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz`),
  /// optionally surrounded by leading and/or trailing ASCII spaces (`0x20`).
  ///
  /// The empty string and a string of only spaces both return `true`
  /// (consistent with `decode`, which accepts these as the encoding of the
  /// empty byte array).
  ///
  /// Embedded spaces (between Base58 characters) and any character outside
  /// the alphabet (e.g. `'0'`, `'O'`, `'I'`, `'l'`, non-ASCII bytes) cause
  /// this function to return `false`.
  ///
  /// Example:
  /// ```motoko include=import
  /// let ok = Base58.isBase58Alphabet("1AGNa15ZQXAZUgFiqJ2i7Z2DPU2J6hW62i");
  /// ```
  ///
  /// Never traps.
  public func isBase58Alphabet(input : Text) : Bool {
    let bytes : Blob = Text.encodeUtf8(input);
    let size = bytes.size();
    var pos : Nat = 0;

    // Skip leading spaces.
    while (pos < size and bytes[pos] == 0x20) {
      pos += 1;
    };

    // Find end of payload (before trailing spaces).
    var endPos = size;
    while (endPos > pos and bytes[endPos - 1] == 0x20) {
      endPos -= 1;
    };

    // All bytes in [pos, endPos) must map to a Base58 alphabet index.
    while (pos < endPos) {
      if (mapBase58[bytes[pos].toNat()] == 255) {
        return false;
      };
      pos += 1;
    };

    true;
  };

  /// Decodes a Base58-encoded string to a byte array, returning `null`
  /// instead of trapping when `input` contains characters outside the
  /// Base58 alphabet.
  ///
  /// Equivalent to checking `isBase58Alphabet(input)` first and then
  /// calling `decode(input)`. Leading and trailing spaces are accepted (see
  /// `decode` for the exact semantics).
  ///
  /// Example:
  /// ```motoko include=import
  /// let result = Base58.decodeOpt("1AGNa15ZQXAZUgFiqJ2i7Z2DPU2J6hW62i");
  /// ```
  ///
  /// Returns `?bytes` on success and `null` if `input` is not valid in the
  /// Base58 alphabet. Never traps.
  public func decodeOpt(input : Text) : ?[Nat8] {
    if (not isBase58Alphabet(input)) {
      return null;
    };
    ?decode(input);
  };

  /// Decodes a Base58-encoded string to a byte array.
  ///
  /// Leading `'1'` characters in the input are preserved as leading zero bytes
  /// in the output. Leading and trailing spaces are ignored.
  ///
  /// Example:
  /// ```motoko include=import
  /// let bytes = Base58.decode("1AGNa15ZQXAZUgFiqJ2i7Z2DPU2J6hW62i");
  /// ```
  ///
  /// Traps if `input_` contains any byte that is not a leading space, a
  /// trailing space, or a character in the Base58 alphabet
  /// (`123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz`). In
  /// particular, spaces embedded inside the payload, ASCII characters such
  /// as `'0'`, `'O'`, `'I'`, `'l'`, and any non-ASCII byte all trap.
  public func decode(input_ : Text) : [Nat8] {
    let input : Blob = Text.encodeUtf8(input_);
    let inputSize = input.size();
    var pos : Nat = 0;

    // Skip leading spaces.
    while (pos < inputSize and input[pos] == 0x20) {
      pos += 1;
    };

    // Skip and count leading '1's.
    let startPos = pos;
    while (pos < inputSize and input[pos] == 0x31) {
      pos += 1;
    };
    let zeroes : Nat = pos - startPos;

    // Find end of base58 payload (before trailing spaces).
    var endPos = inputSize;
    while (endPos > pos and input[endPos - 1] == 0x20) {
      endPos -= 1;
    };
    let digitCount : Nat = endPos - pos;

    // Allocate base256 buffer: log(58)/log(256) ≈ 733/1000.
    let size : Nat = digitCount * 733 / 1000 + 1;
    let b256 : [var Nat16] = VarArray.repeat<Nat16>(0x00, size);
    var length : Nat = 0;

    // Process leading remainder digits (digitCount % 8) one at a time.
    let remainder = digitCount % 8;
    var rem : Nat = 0;
    while (rem < remainder) {
      var carry : Nat16 = Nat16.fromIntWrap(mapBase58[input[pos].toNat()]);
      assert (carry != 0xff);

      var i : Nat = 0;
      var j : Nat = size - 1;
      label inner while (carry != 0 or i < length) {
        carry +%= 58 * b256[j];
        b256[j] := (carry & 0xff);
        carry >>= 8;
        i += 1;
        if (j == 0) break inner;
        j -= 1;
      };

      assert (carry == 0);
      length := i;
      pos += 1;
      rem += 1;
    };

    // Process full batches of 8 digits: b256 = b256 * 58^8 + v.
    // 58^8 = 128_063_081_718_016. Max carry < 2^55, fits in Nat64.
    while (pos < endPos) {
      let d0 = Nat64.fromIntWrap(mapBase58[input[pos].toNat()]);
      let d1 = Nat64.fromIntWrap(mapBase58[input[pos + 1].toNat()]);
      let d2 = Nat64.fromIntWrap(mapBase58[input[pos + 2].toNat()]);
      let d3 = Nat64.fromIntWrap(mapBase58[input[pos + 3].toNat()]);
      let d4 = Nat64.fromIntWrap(mapBase58[input[pos + 4].toNat()]);
      let d5 = Nat64.fromIntWrap(mapBase58[input[pos + 5].toNat()]);
      let d6 = Nat64.fromIntWrap(mapBase58[input[pos + 6].toNat()]);
      let d7 = Nat64.fromIntWrap(mapBase58[input[pos + 7].toNat()]);
      assert (
        d0 != 0xff and d1 != 0xff and d2 != 0xff and d3 != 0xff and d4 != 0xff and d5 != 0xff and d6 != 0xff and d7 != 0xff
      );

      var carry : Nat64 = (((((((d0 *% 58 +% d1) *% 58 +% d2) *% 58 +% d3) *% 58 +% d4) *% 58 +% d5) *% 58 +% d6) *% 58 +% d7);

      var i : Nat = 0;
      var j : Nat = size - 1;
      label inner while (carry != 0 or i < length) {
        carry +%= 128_063_081_718_016 *% b256[j].toNat32().toNat64();
        b256[j] := (carry & 0xff).toNat32().toNat16();
        carry >>= 8;
        i += 1;
        if (j == 0) break inner;
        j -= 1;
      };

      assert (carry == 0);
      length := i;
      pos += 8;
    };

    // Skip trailing spaces.
    while (pos < inputSize and input[pos] == 0x20) {
      pos += 1;
    };

    // Check all input was consumed.
    assert (pos == inputSize);

    // Skip leading zeroes in base256 result.
    var start : Nat = size - length;
    while (start < size and b256[start] == 0) {
      start += 1;
    };

    Array.tabulate<Nat8>(
      zeroes + size - start,
      func(i) {
        if (i < zeroes) 0x00 else b256[i + start - zeroes].toNat8();
      },
    );
  };

  /// Encodes a byte array as a Base58 string.
  ///
  /// Leading zero bytes in the input are preserved as leading `'1'` characters
  /// in the output.
  ///
  /// Example:
  /// ```motoko include=import
  /// let encoded = Base58.encode([0x00, 0x01, 0x02]);
  /// ```
  ///
  /// Never traps. Accepts any byte array, including the empty array.
  public func encode(input : [Nat8]) : Text {
    let inputSize = input.size();
    var length : Nat = 0;
    var pos : Nat = 0;

    // Skip & count leading zeroes.
    while (pos < inputSize and input[pos] == 0) {
      pos += 1;
    };
    let zeroes : Nat = pos;

    // Allocate enough space in big-endian base58 representation:
    // log(256) / log(58), rounded up.
    let bytesCount : Nat = inputSize - pos;
    let size : Nat = bytesCount * 138 / 100 + 1;
    let b58 : [var Nat16] = VarArray.repeat<Nat16>(0, size);

    // Process leading remainder bytes (bytesCount % 7) one at a time.
    let remainder = bytesCount % 7;
    var rem : Nat = 0;
    while (rem < remainder) {
      var carry : Nat16 = input[pos].toNat16();
      var i : Nat = 0;
      var b58Pointer : Nat = size - 1;
      label inner while (carry != 0 or i < length) {
        carry +%= 256 *% b58[b58Pointer];
        b58[b58Pointer] := carry % 58;
        carry /= 58;
        i += 1;
        if (b58Pointer == 0) break inner;
        b58Pointer -= 1;
      };
      assert (carry == 0);
      length := i;
      pos += 1;
      rem += 1;
    };

    // Process full batches of 7 bytes: b58 = b58 * 256^7 + v.
    // 256^7 = 72_057_594_037_927_936. Max carry < 2^62, fits in Nat64.
    while (pos < inputSize) {
      var carry : Nat64 = Nat64.fromIntWrap(input[pos].toNat()) << 48 | Nat64.fromIntWrap(input[pos + 1].toNat()) << 40 | Nat64.fromIntWrap(input[pos + 2].toNat()) << 32 | Nat64.fromIntWrap(input[pos + 3].toNat()) << 24 | Nat64.fromIntWrap(input[pos + 4].toNat()) << 16 | Nat64.fromIntWrap(input[pos + 5].toNat()) << 8 | Nat64.fromIntWrap(input[pos + 6].toNat());

      var i : Nat = 0;
      var b58Pointer : Nat = size - 1;
      label inner while (carry != 0 or i < length) {
        carry +%= 72_057_594_037_927_936 *% b58[b58Pointer].toNat32().toNat64();
        b58[b58Pointer] := (carry % 58).toNat32().toNat16();
        carry /= 58;
        i += 1;
        if (b58Pointer == 0) break inner;
        b58Pointer -= 1;
      };
      assert (carry == 0);
      length := i;
      pos += 7;
    };

    // Skip leading zeroes in base58 result.
    var b58Pointer : Nat = size - length;
    while (b58Pointer < size and b58[b58Pointer] == 0) {
      b58Pointer += 1;
    };

    let outputBytes = Array.tabulate<Nat8>(
      zeroes + size - b58Pointer,
      func(i) {
        if (i < zeroes) {
          0x31 : Nat8;
        } else {
          base58Alphabet[b58[b58Pointer + i - zeroes].toNat()];
        };
      },
    );

    arrayToText(outputBytes);
  };
};
