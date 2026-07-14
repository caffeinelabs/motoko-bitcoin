/// Base58Check encoding and decoding for binary data.
///
/// Base58Check extends Base58 by appending a 4-byte checksum derived from
/// a double SHA-256 hash of the payload. This detects transcription errors
/// when users copy Bitcoin addresses.
///
/// Import from the bitcoin package to use this module.
/// ```motoko name=import
/// import Base58Check "mo:bitcoin/Base58Check";
/// ```

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Nat "mo:core/Nat";
import VarArray "mo:core/VarArray";

import Sha256 "mo:sha2/Sha256";

import Base58 "Base58";

module {

  /// Encodes a byte array to a Base58Check string by appending a 4-byte checksum.
  ///
  /// Example:
  /// ```motoko include=import
  /// let encoded = Base58Check.encode([0x00, 0x01, 0x02]);
  /// ```
  ///
  /// Never traps. Accepts any byte array, including the empty array.
  public func encode(input : [Nat8]) : Text {
    // Add 4-byte hash check to the end.
    let hash : [Nat8] = Sha256.fromBlob(#sha256, Sha256.fromArray(#sha256, input)).toArray();
    let inputWithCheck : [var Nat8] = VarArray.repeat<Nat8>(0, input.size() + 4);

    for (i in Nat.range(0, input.size())) {
      inputWithCheck[i] := input[i];
    };

    inputWithCheck[input.size()] := hash[0];
    inputWithCheck[input.size() + 1] := hash[1];
    inputWithCheck[input.size() + 2] := hash[2];
    inputWithCheck[input.size() + 3] := hash[3];

    Base58.encode(inputWithCheck.toArray());
  };

  /// Decodes a Base58Check string, verifying the embedded 4-byte checksum.
  ///
  /// On success, returns `?payload` where `payload` is the original byte
  /// array passed to `encode` (i.e. with the 4 checksum bytes already
  /// stripped). The first byte is conventionally a Bitcoin version byte
  /// (e.g. `0x00` for mainnet P2PKH, `0x6f` for testnet P2PKH, `0x80` for
  /// mainnet WIF) but this function does not interpret it.
  ///
  /// Example:
  /// ```motoko include=import
  /// let decoded = Base58Check.decode("1AGNa15ZQXAZUgFiqJ2i7Z2DPU2J6hW62i");
  /// ```
  ///
  /// Returns `null` when:
  /// - the Base58 decoding of `input` produces fewer than 4 bytes (so there
  ///   is no room for the 4-byte checksum), or
  /// - the trailing 4 checksum bytes do not match the double-SHA256 of the
  ///   payload.
  ///
  /// Traps if `input` contains any character outside the Base58 alphabet
  /// (propagated from `Base58.decode`). For fully graceful parsing of
  /// arbitrary user input, validate the character set first.
  public func decode(input : Text) : ?[Nat8] {
    let decoded : [Nat8] = Base58.decode(input);

    if (decoded.size() < 4) {
      return null;
    };

    // Strip the last 4 bytes.
    let output = Array.tabulate<Nat8>(
      decoded.size() - 4,
      func(i) {
        decoded[i];
      },
    );

    // Re-calculate checksum, ensure it matches the included 4-byte checksum.
    let hash : [Nat8] = Sha256.fromBlob(#sha256, Sha256.fromArray(#sha256, output)).toArray();

    for (i in Nat.range(0, 4)) {
      if (hash[i] != decoded[decoded.size() - 4 + i]) {
        return null;
      };
    };

    return ?output;
  };
};
