/// Low-level binary read/write utilities for big-endian and little-endian integers.
///
/// Provides helpers to read and write multi-byte integers from and to byte
/// arrays at a given offset. Used throughout the Bitcoin protocol for
/// serializing and deserializing data structures.
///
/// **Bounds:** every function in this module performs raw indexed access at
/// the supplied `offset` and traps if `offset + N > bytes.size()`, where `N`
/// is the integer width in bytes (4 for `*32`, 8 for `*64`, 16 for `*128`,
/// 32 for `*256`, 2 for `writeLE16`, and `count` for `copy`). Callers are
/// responsible for sizing the buffer correctly.
///
/// Import from the bitcoin package to use this module.
/// ```motoko name=import
/// import Common "mo:bitcoin/Common";
/// ```

import Nat "mo:core/Nat";
import Nat16 "mo:core/Nat16";
import Nat32 "mo:core/Nat32";
import Nat64 "mo:core/Nat64";
import Nat8 "mo:core/Nat8";

module {
  /// Reads a 32-bit unsigned integer in big-endian byte order from `bytes` starting at `offset`.
  ///
  /// Example:
  /// ```motoko include=import
  /// let value = Common.readBE32([0x01, 0x02, 0x03, 0x04], 0);
  /// assert value == 0x01020304;
  /// ```
  ///
  /// Traps if `offset + 4 > bytes.size()`.
  // Read big endian 32-bit natural number starting at offset.
  public func readBE32(bytes : [Nat8], offset : Nat) : Nat32 {
    bytes[offset + 0].toNat16().toNat32() << 24 | bytes[offset + 1].toNat16().toNat32() << 16 | bytes[offset + 2].toNat16().toNat32() << 8 | bytes[offset + 3].toNat16().toNat32();
  };

  /// Reads a 64-bit unsigned integer in big-endian byte order from `bytes` starting at `offset`.
  ///
  /// Example:
  /// ```motoko include=import
  /// let buf : [Nat8] = [0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04];
  /// let value = Common.readBE64(buf, 0);
  /// assert value == 0x0000000001020304;
  /// ```
  ///
  /// Traps if `offset + 8 > bytes.size()`.
  // Read big endian 64-bit natural number starting at offset.
  public func readBE64(bytes : [Nat8], offset : Nat) : Nat64 {
    let first : Nat32 = readBE32(bytes, offset);
    let second : Nat32 = readBE32(bytes, offset + 4);

    first.toNat64() << 32 | second.toNat64();
  };

  /// Reads a 128-bit unsigned integer in big-endian byte order from `bytes` starting at `offset`.
  ///
  /// Example:
  /// ```motoko include=import
  /// let value = Common.readBE128([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04], 0);
  /// ```
  ///
  /// Traps if `offset + 16 > bytes.size()`.
  // Read big endian 128-bit natural number starting at offset.
  public func readBE128(bytes : [Nat8], offset : Nat) : Nat {
    let first : Nat64 = readBE64(bytes, offset);
    let second : Nat64 = readBE64(bytes, offset + 8);

    first.toNat() * 0x10000000000000000 + second.toNat();
  };

  /// Reads a 256-bit unsigned integer in big-endian byte order from `bytes` starting at `offset`.
  ///
  /// Used for reading elliptic curve scalars and coordinates.
  ///
  /// Example:
  /// ```motoko include=import
  /// // Read a 256-bit value from a 32-byte array
  /// // let value = Common.readBE256(bytes32, 0);
  /// ```
  ///
  /// Traps if `offset + 32 > bytes.size()`.
  // Read big endian 256-bit natural number starting at offset.
  public func readBE256(bytes : [Nat8], offset : Nat) : Nat {
    let first : Nat = readBE128(bytes, offset);
    let second : Nat = readBE128(bytes, offset + 16);

    first * 0x100000000000000000000000000000000 + second;
  };

  /// Writes `value` as a 32-bit big-endian integer into `bytes` at `offset`.
  ///
  /// Example:
  /// ```motoko include=import
  /// import VarArray "mo:core/VarArray";
  /// let buf = VarArray.repeat<Nat8>(0, 4);
  /// Common.writeBE32(buf, 0, 0x01020304);
  /// assert buf[0] == 0x01;
  /// ```
  ///
  /// Traps if `offset + 4 > bytes.size()`.
  // Write given value as 32-bit big endian into array starting at offset.
  public func writeBE32(bytes : [var Nat8], offset : Nat, value : Nat32) {
    bytes[offset] := ((value & 0xFF000000) >> 24).toNat16().toNat8();
    bytes[offset + 1] := ((value & 0xFF0000) >> 16).toNat16().toNat8();
    bytes[offset + 2] := ((value & 0xFF00) >> 8).toNat16().toNat8();
    bytes[offset + 3] := (value & 0xFF).toNat16().toNat8();
  };

  /// Writes `value` as a 64-bit big-endian integer into `bytes` at `offset`.
  ///
  /// Example:
  /// ```motoko include=import
  /// import VarArray "mo:core/VarArray";
  /// let buf = VarArray.repeat<Nat8>(0, 8);
  /// Common.writeBE64(buf, 0, 0x0102030405060708);
  /// ```
  ///
  /// Traps if `offset + 8 > bytes.size()`.
  // Write given value as 64-bit big endian into array starting at offset.
  public func writeBE64(bytes : [var Nat8], offset : Nat, value : Nat64) {
    let first : Nat32 = Nat32.fromIntWrap((value >> 32).toNat());
    let second : Nat32 = Nat32.fromIntWrap(value.toNat());

    writeBE32(bytes, offset, first);
    writeBE32(bytes, offset + 4, second);
  };

  /// Writes `value` as a 128-bit big-endian integer into `bytes` at `offset`.
  ///
  /// Traps if `offset + 16 > bytes.size()`.
  // Write given value as 128-bit big endian into array starting at offset.
  public func writeBE128(bytes : [var Nat8], offset : Nat, value : Nat) {
    let first : Nat64 = Nat64.fromIntWrap(value / 0x10000000000000000);
    let second : Nat64 = Nat64.fromIntWrap(value);

    writeBE64(bytes, offset, first);
    writeBE64(bytes, offset + 8, second);
  };

  /// Writes `value` as a 256-bit big-endian integer into `bytes` at `offset`.
  ///
  /// Traps if `offset + 32 > bytes.size()`.
  // Write given value as 256-bit big endian into array starting at offset.
  public func writeBE256(bytes : [var Nat8], offset : Nat, value : Nat) {
    let first : Nat = value / (2 ** 128);
    let second : Nat = value - (first * 0x100000000000000000000000000000000);

    writeBE128(bytes, offset, first);
    writeBE128(bytes, offset + 16, second);
  };

  /// Reads a 32-bit unsigned integer in little-endian byte order from `bytes` starting at `offset`.
  ///
  /// Example:
  /// ```motoko include=import
  /// let value = Common.readLE32([0x04, 0x03, 0x02, 0x01], 0);
  /// assert value == 0x01020304;
  /// ```
  ///
  /// Traps if `offset + 4 > bytes.size()`.
  // Read little endian 32-bit natural number starting at offset.
  public func readLE32(bytes : [Nat8], offset : Nat) : Nat32 {
    bytes[offset + 3].toNat16().toNat32() << 24 | bytes[offset + 2].toNat16().toNat32() << 16 | bytes[offset + 1].toNat16().toNat32() << 8 | bytes[offset + 0].toNat16().toNat32();
  };

  /// Writes `value` as a 16-bit little-endian integer into `bytes` at `offset`.
  ///
  /// Traps if `offset + 2 > bytes.size()`.
  // Write given value as 16-bit little endian into array starting at offset.
  public func writeLE16(bytes : [var Nat8], offset : Nat, value : Nat16) {
    let first : Nat8 = Nat8.fromIntWrap(value.toNat());
    let second : Nat8 = Nat8.fromIntWrap((value >> 8).toNat());

    bytes[offset] := first;
    bytes[offset + 1] := second;
  };

  /// Writes `value` as a 32-bit little-endian integer into `bytes` at `offset`.
  ///
  /// Example:
  /// ```motoko include=import
  /// import VarArray "mo:core/VarArray";
  /// let buf = VarArray.repeat<Nat8>(0, 4);
  /// Common.writeLE32(buf, 0, 0x01020304);
  /// assert buf[0] == 0x04;
  /// ```
  ///
  /// Traps if `offset + 4 > bytes.size()`.
  // Write given value as 32-bit little endian into array starting at offset.
  public func writeLE32(bytes : [var Nat8], offset : Nat, value : Nat32) {
    let first : Nat16 = Nat16.fromIntWrap(value.toNat());
    let second : Nat16 = Nat16.fromIntWrap((value >> 16).toNat());

    writeLE16(bytes, offset, first);
    writeLE16(bytes, offset + 2, second);
  };

  /// Writes `value` as a 64-bit little-endian integer into `bytes` at `offset`.
  ///
  /// Traps if `offset + 8 > bytes.size()`.
  // Write given value as 64-bit little endian into array starting at offset.
  public func writeLE64(bytes : [var Nat8], offset : Nat, value : Nat64) {
    let first : Nat32 = Nat32.fromIntWrap(value.toNat());
    let second : Nat32 = Nat32.fromIntWrap((value >> 32).toNat());

    writeLE32(bytes, offset, first);
    writeLE32(bytes, offset + 4, second);
  };

  /// Copies `count` bytes from `src` starting at `srcOffset` into `dest` starting at `destOffset`.
  ///
  /// Traps if `destOffset + count > dest.size()` or
  /// `srcOffset + count > src.size()`.
  // Copy data from src into dest from/at the given offsets.
  public func copy(
    dest : [var Nat8],
    destOffset : Nat,
    src : [Nat8],
    srcOffset : Nat,
    count : Nat,
  ) {
    for (i in Nat.range(0, count)) {
      dest[destOffset + i] := src[srcOffset + i];
    };
  };
};
