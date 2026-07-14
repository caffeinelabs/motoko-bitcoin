/// Utilities for reading and writing Bitcoin-serialized binary data.
///
/// Provides functions to read integers and variable-length data from
/// iterators, and to encode values using Bitcoin's variable-length integer
/// (varint) format.
///
/// Import from the bitcoin package to use this module.
/// ```motoko name=import
/// import ByteUtils "mo:bitcoin/ByteUtils";
/// ```

import Nat16 "mo:core/Nat16";
import Nat32 "mo:core/Nat32";
import Nat64 "mo:core/Nat64";
import Nat8 "mo:core/Nat8";
import { type Iter } "mo:core/Types";
import VarArray "mo:core/VarArray";

import Common "Common";

module {
  /// Reads `count` bytes from `data`, returning them as an array.
  ///
  /// If `reverse` is `true`, the bytes are stored in reverse order.
  ///
  /// Example:
  /// ```motoko include=import
  /// let bytes = ByteUtils.read([1, 2, 3, 4].values(), 3, false);
  /// ```
  ///
  /// Never traps. Returns `null` if `data` is exhausted before `count`
  /// bytes have been read. When `count == 0`, returns `?[]` immediately
  /// without consuming any input.
  // Read a number of elements from the given iterator and return as array. If
  // reverse is true, will read return the elements in reverse order.
  // Returns null if the iterator does not produce enough data.
  public func read(
    data : Iter<Nat8>,
    count : Nat,
    reverse : Bool,
  ) : ?[Nat8] {
    do ? {
      if (count == 0) return ?[];

      let readData : [var Nat8] = VarArray.repeat<Nat8>(0, count);
      if (reverse) {
        var nextReadIndex : Nat = count - 1;

        label Loop loop {
          readData[nextReadIndex] := data.next()!;
          if (nextReadIndex == 0) {
            break Loop;
          };
          nextReadIndex -= 1;
        };
      } else {
        var nextReadIndex : Nat = 0;

        while (nextReadIndex < count) {
          readData[nextReadIndex] := data.next()!;
          nextReadIndex += 1;
        };
      };

      readData.toArray();
    };
  };

  /// Reads a 16-bit unsigned integer in little-endian byte order from `data`.
  ///
  /// Never traps. Returns `null` if `data` does not yield at least 2 bytes.
  // Read little endian 16-bit natural number starting at offset.
  // Returns null if the iterator does not produce enough data.
  public func readLE16(data : Iter<Nat8>) : ?Nat16 {
    do ? {
      let (a, b) = (data.next()!, data.next()!);
      b.toNat16() << 8 | a.toNat16();
    };
  };

  /// Reads a 32-bit unsigned integer in little-endian byte order from `data`.
  ///
  /// Never traps. Returns `null` if `data` does not yield at least 4 bytes.
  // Read little endian 32-bit natural number starting at offset.
  // Returns null if the iterator does not produce enough data.
  public func readLE32(data : Iter<Nat8>) : ?Nat32 {
    do ? {
      let (a, b, c, d) = (data.next()!, data.next()!, data.next()!, data.next()!);
      d.toNat16().toNat32() << 24 | c.toNat16().toNat32() << 16 | b.toNat16().toNat32() << 8 | a.toNat16().toNat32();
    };
  };

  /// Reads a 64-bit unsigned integer in little-endian byte order from `data`.
  ///
  /// Never traps. Returns `null` if `data` does not yield at least 8 bytes.
  // Read little endian 64-bit natural number starting at offset.
  // Returns null if the iterator does not produce enough data.
  public func readLE64(data : Iter<Nat8>) : ?Nat64 {
    do ? {
      let (a, b, c, d, e, f, g, h) = (
        data.next()!,
        data.next()!,
        data.next()!,
        data.next()!,
        data.next()!,
        data.next()!,
        data.next()!,
        data.next()!,
      );

      h.toNat16().toNat32().toNat64() << 56 | g.toNat16().toNat32().toNat64() << 48 | f.toNat16().toNat32().toNat64() << 40 | e.toNat16().toNat32().toNat64() << 32 | d.toNat16().toNat32().toNat64() << 24 | c.toNat16().toNat32().toNat64() << 16 | b.toNat16().toNat32().toNat64() << 8 | a.toNat16().toNat32().toNat64();
    };
  };

  /// Reads a single byte from `data`.
  ///
  /// Never traps. Returns `null` if `data` is exhausted.
  // Read one element from the given iterator.
  // Returns null if the iterator does not produce enough data.
  public func readOne(data : Iter<Nat8>) : ?Nat8 {
    data.next();
  };

  /// Reads a Bitcoin variable-length integer (varint) from `data`.
  ///
  /// Varints encode values in 1 byte (`< 0xfd`), 3 bytes (prefix `0xfd`,
  /// `Nat16` LE), 5 bytes (prefix `0xfe`, `Nat32` LE), or 9 bytes
  /// (prefix `0xff`, `Nat64` LE).
  ///
  /// Never traps. Returns `null` when `data` is exhausted before the
  /// expected payload bytes have been read for the chosen prefix.
  // Read and return a varint encoded integer from data.
  // Returns null if the iterator does not produce enough data.
  public func readVarint(data : Iter<Nat8>) : ?Nat {
    do ? {
      switch (readOne(data)!) {
        case 0xfd {
          readLE16(data)!.toNat();
        };
        case 0xfe {
          readLE32(data)!.toNat();
        };
        case 0xff {
          readLE64(data)!.toNat();
        };
        case (length) {
          length.toNat();
        };
      };
    };
  };

  /// Encodes `value` as a Bitcoin variable-length integer (varint).
  ///
  /// Returns a 1-, 3-, 5-, or 9-byte array depending on the magnitude of `value`.
  ///
  /// Example:
  /// ```motoko include=import
  /// let encoded = ByteUtils.writeVarint(252); // [0xfc]
  /// let encoded2 = ByteUtils.writeVarint(253); // [0xfd, 0xfd, 0x00]
  /// ```
  ///
  /// Traps if `value >= 2^64` (the largest representable varint).
  // Encode value as varint.
  public func writeVarint(value : Nat) : [Nat8] {
    assert (value < 0x10000000000000000);

    if (value < 0xfd) { [Nat8.fromIntWrap(value)] } else if (value < 0x10000) {
      let buf = VarArray.repeat<Nat8>(0xfd, 3);
      Common.writeLE16(buf, 1, Nat16.fromIntWrap(value));
      buf.toArray();
    } else if (value < 0x100000000) {
      let buf = VarArray.repeat<Nat8>(0xfe, 5);
      Common.writeLE32(buf, 1, Nat32.fromIntWrap(value));
      buf.toArray();
    } else {
      let buf = VarArray.repeat<Nat8>(0xff, 9);
      Common.writeLE64(buf, 1, Nat64.fromIntWrap(value));
      buf.toArray();
    };
  };
};
