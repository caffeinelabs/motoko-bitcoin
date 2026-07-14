/// Common Bitcoin hash functions.
///
/// Provides SHA256, RIPEMD160, and Bitcoin-specific hash operations
/// used throughout the Bitcoin protocol.
///
/// Import from the bitcoin package to use this module.
/// ```motoko name=import
/// import Hash "mo:bitcoin/Hash";
/// ```

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Text "mo:core/Text";

import Sha256 "mo:sha2/Sha256";

import Ripemd160 "Ripemd160";

module {
  /// Applies SHA-256 followed by RIPEMD-160 to the given data.
  ///
  /// This is the `HASH160` operation used in Bitcoin scripts.
  ///
  /// Example:
  /// ```motoko include=import
  /// let hash = Hash.hash160([0x01, 0x02, 0x03]);
  /// ```
  ///
  /// Never traps. Always returns a 20-byte digest.
  // Applies SHA256 followed by RIPEMD160 on the given data.
  public func hash160(data : [Nat8]) : [Nat8] {
    Ripemd160.hash(Sha256.fromArray(#sha256, data).toArray());
  };

  /// Applies double SHA-256 (SHA256d) to the given data.
  ///
  /// This is used in Bitcoin for computing transaction IDs, block hashes,
  /// and other values throughout the protocol.
  ///
  /// Example:
  /// ```motoko include=import
  /// let hash = Hash.doubleSHA256([0x01, 0x02, 0x03]);
  /// ```
  ///
  /// Never traps. Always returns a 32-byte digest.
  // Applies double SHA256 to input.
  public func doubleSHA256(data : [Nat8]) : [Nat8] {
    Sha256.fromBlob(#sha256, Sha256.fromArray(#sha256, data)).toArray();
  };

  /// Computes a tagged hash as defined in BIP-340.
  ///
  /// The tagged hash is `SHA256(SHA256(tag) || SHA256(tag) || data)`, where
  /// `tag` is a UTF-8 encoded domain-separation string. This is used in
  /// Taproot to prevent hash collisions across different protocol contexts.
  ///
  /// Example:
  /// ```motoko include=import
  /// let hash = Hash.taggedHash([0x01, 0x02], "TapTweak");
  /// ```
  ///
  /// Never traps. Always returns a 32-byte digest.
  public func taggedHash(data : [Nat8], tag : Text) : [Nat8] {
    let tag_hash = Sha256.fromBlob(#sha256, tag.encodeUtf8()).toArray();
    Sha256.fromArray(#sha256, [tag_hash, tag_hash, data].flatten()).toArray();
  };
};
