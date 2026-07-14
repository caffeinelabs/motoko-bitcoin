/// BIP32 extended public key parsing, derivation, and serialization.
///
/// Provides utilities to parse `xpub` strings, derive non-hardened child keys,
/// and serialize extended public keys.
///
/// Import from the bitcoin package to use this module.
/// ```motoko name=import
/// import Bip32 "mo:bitcoin/Bip32";
/// ```

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Iter "mo:core/Iter";
import Nat "mo:core/Nat";
import Nat32 "mo:core/Nat32";
import Text "mo:core/Text";
import { type Iter } "mo:core/Types";
import VarArray "mo:core/VarArray";

import Affine "ec/Affine";
import Base58Check "Base58Check";
import Common "Common";
import Curves "ec/Curves";
import Hash "Hash";
import Hmac "Hmac";
import Jacobi "ec/Jacobi";

module {
  /// Child derivation path representation.
  ///
  /// `#text` expects a string such as `"m/0/1"`.
  /// `#array` uses already parsed child indices.
  public type Path = {
    #text : Text;
    #array : [Nat32];
  };

  /// Optional parent public key information used for fingerprint validation.
  ///
  /// `#publicKeyData` is a compressed SEC1 public key.
  /// `#fingerprint` is a 4-byte HASH160 fingerprint.
  public type ParentPublicKey = {
    #publicKeyData : [Nat8];
    #fingerprint : [Nat8];
  };

  let curve : Curves.Curve = Curves.secp256k1;
  let publicPrefix : Nat32 = 0x0488B21E;

  /// Parses a Base58Check-encoded BIP32 extended public key.
  ///
  /// If `_parentPubKey` is `#publicKeyData`, validates that its fingerprint
  /// matches the parsed key. If `_parentPubKey` is non-empty `#fingerprint`,
  /// validates against that fingerprint. For empty `#fingerprint`, the parsed
  /// fingerprint is inherited.
  ///
  /// Example:
  /// ```motoko include=import
  /// let parsed = Bip32.parse(xpub, null);
  /// ```
  ///
  /// Returns `null` when:
  /// - `bip32Key` is not valid Base58Check (alphabet error or checksum
  ///   mismatch).
  /// - The version prefix is not `0x0488B21E` (mainnet `xpub`).
  /// - At depth 0 (master key) the parent fingerprint is non-zero, the
  ///   index is non-zero, or a non-`null` `_parentPubKey` is provided.
  /// - At depth > 0 the parsed fingerprint does not match the supplied
  ///   `_parentPubKey` data or fingerprint, or `_parentPubKey` is `null`.
  /// - The compressed key prefix byte is not `0x02` or `0x03`.
  /// - The 33-byte key does not decode to a point on the secp256k1 curve.
  ///
  /// Traps if the Base58Check payload is shorter than 78 bytes (out-of-bounds
  /// access on the fixed-offset reads of version, depth, fingerprint, index,
  /// chaincode, and key).
  // Parse a Bip32 serialized key. If _parentPubKey is #publicKeyData, will
  // verify the fingerprint within the parsed key. If _parentPubKey is
  // non-empty #fingerprint, will verify the fingerprint against those values.
  // If _parentPubKey is empty #fingerprint, will inherit the parsed fingerprint
  // without verification.
  public func parse(bip32Key : Text, _parentPubKey : ?ParentPublicKey) : ?ExtendedPublicKey {
    switch (Base58Check.decode(bip32Key)) {
      case (?b58Decoded) {
        let version : Nat32 = Common.readBE32(b58Decoded, 0);
        if (version != publicPrefix) {
          return null;
        };

        let depth : Nat8 = b58Decoded[4];
        let fingerprint : [Nat8] = Array.tabulate<Nat8>(
          4,
          func(i) {
            b58Decoded[5 + i];
          },
        );
        let index : Nat32 = Common.readBE32(b58Decoded, 9);
        var parentPubKey = _parentPubKey;

        if (depth == 0) {
          // With depth = 0 we are parsing the master public key which must be
          // of index > 0 and does not have a parent.
          if (
            parentPubKey != null or fingerprint != [0, 0, 0, 0] or
            index > 0
          ) {
            return null;
          };
        } else {
          // Parsing a child public key.
          // Verify that the specified parent public key or its fingerprint
          // matches the parsed fingerprint.
          switch (parentPubKey) {
            case (?(#publicKeyData publicKeyData)) {
              let parentPubKeyHash = Hash.hash160(publicKeyData);
              for (i in Nat.range(0, 4)) {
                if (parentPubKeyHash[i] != fingerprint[i]) {
                  return null;
                };
              };
            };
            case (?(#fingerprint parentPublicKeyFingerprint)) {
              if (parentPublicKeyFingerprint.size() > 0) {
                for (i in Nat.range(0, 4)) {
                  if (parentPublicKeyFingerprint[i] != fingerprint[i]) {
                    return null;
                  };
                };
              } else {
                parentPubKey := ?(#fingerprint(fingerprint));
              };
            };
            case (null) {
              return null;
            };
          };
        };

        let chaincode = Array.tabulate<Nat8>(
          32,
          func(i) {
            b58Decoded[13 + i];
          },
        );

        // Public key must start with 0x02 or 0x03.
        if (b58Decoded[45] != 0x02 and b58Decoded[45] != 0x03) {
          return null;
        };

        let keyData = Array.tabulate<Nat8>(
          33,
          func(i) {
            b58Decoded[45 + i];
          },
        );

        switch (Affine.fromBytes(keyData, curve)) {
          case (null) {
            return null;
          };
          case (?parsedPoint) {
            if (not Affine.isOnCurve(parsedPoint)) {
              return null;
            };
            return ?ExtendedPublicKey(keyData, chaincode, depth, index, parentPubKey);
          };
        };
      };
      case (null) {
        // Parsing as b58 string failed.
        return null;
      };
    };
  };

  func isHardenedIndex(index : Nat32) : Bool {
    index >= 0x80000000 // 2**31
  };

  /// Parses a textual path like `"m/0/1/2"` into child indices.
  ///
  /// Whitespace and a leading `"m/"` prefix are stripped. Each remaining
  /// `'/'`-separated segment must be a non-negative decimal integer in the
  /// `Nat32` range.
  ///
  /// Example:
  /// ```motoko include=import
  /// let path = Bip32.arrayPathFromString("m/0/1/2");
  /// ```
  ///
  /// Never traps. Returns `null` when:
  /// - any segment is not a valid decimal `Nat`,
  /// - any segment is `≥ 2^32`,
  /// - hardened markers (e.g. `m/0'`) are present (parsed as non-numeric).
  // Parses a Text path in the form "m/a/b/c/..." for unsigned integers
  // a,b,c,... and returns an array [a, b, c, ...]. Parsing fails and returns
  // null if input is not in the expected format or if it contains hardened
  // indices (e.g., m/0/1').
  public func arrayPathFromString(path : Text) : ?[Nat32] {
    // Initial size most suitable for single-digit indices

    let sanitized : Text = path.replace(
      #predicate(
        func(c) {
          c == '\n' or c == ' ' or c == '\r';
        }
      ),
      "",
    );

    let trimmed : Text = switch (sanitized.stripStart(#text "m/")) {
      case (?t) t;
      case (null) sanitized;
    };

    let tokens : Iter<Text> = trimmed.split(#char '/');

    var valid = true;

    let res = ?tokens.map(
      func(token) {
        switch (Nat.fromText(token)) {
          case (?number) {
            if (number >= 2 ** 32) valid := false;
            Nat32.fromIntWrap(number);
          };
          case (null) {
            valid := false;
            0 : Nat32;
          };
        };
      }
    ).toArray();

    if (valid) res else null;
  };

  /// A BIP32 extended public key.
  ///
  /// Supports non-hardened child derivation and Base58Check serialization.
  ///
  /// Constructor arguments:
  /// - `_key` — 33-byte compressed SEC1 public key (`0x02` or `0x03`
  ///   prefix followed by the 32-byte x coordinate).
  /// - `_chaincode` — 32-byte chain code from the BIP32 derivation.
  /// - `_depth` — derivation depth (`0` for the master key).
  /// - `_index` — child index relative to the parent (`0` at depth `0`).
  ///   Indices `< 2^31` are non-hardened; indices `>= 2^31` are hardened
  ///   and cannot be derived from a public key alone.
  /// - `_parentPublicKey` — parent identification: `null` at depth `0`,
  ///   `?#publicKeyData` for the full 33-byte compressed parent key, or
  ///   `?#fingerprint` for just the 4-byte HASH160 fingerprint.
  ///
  /// Calls to `serialize` and `deriveChild` rely on these sizes; passing
  /// shorter arrays will cause out-of-bounds traps later.
  ///
  /// Example:
  /// ```motoko include=import
  /// let xpub = Bip32.ExtendedPublicKey(key, chaincode, 0, 0, null);
  /// let child = xpub.deriveChild(0);
  /// ```
  // Representation of a BIP32 extended public key.
  public class ExtendedPublicKey(
    _key : [Nat8],
    _chaincode : [Nat8],
    _depth : Nat8,
    _index : Nat32,
    _parentPublicKey : ?ParentPublicKey,
  ) {

    /// Compressed SEC1 public key bytes.
    public let key = _key;
    /// Chain code for child derivation.
    public let chaincode = _chaincode;
    /// Depth in the derivation tree (`0` for master).
    public let depth = _depth;
    /// Child index relative to parent.
    public let index = _index;
    /// Optional parent key data or fingerprint.
    public let parentPublicKey = _parentPublicKey;

    /// Derives a descendant key by applying all indices in `path`.
    ///
    /// Never traps. Returns `null` when:
    /// - `path` is `#text` and `arrayPathFromString` rejects it (see that
    ///   function for the exact rules), or
    /// - any individual `deriveChild` step fails (see `deriveChild`).
    // Derive a child public key with path relative to this instance. Returns
    // null if path is #text and cannot be parsed.
    public func derivePath(path : Path) : ?ExtendedPublicKey {
      do ? {
        // Normalize the given path as an array of indices.
        let pathArray : [Nat32] = switch (path) {
          case (#array path) {
            path;
          };
          case (#text path) {
            arrayPathFromString(path)!;
          };
        };

        var target : ExtendedPublicKey = ExtendedPublicKey(
          key,
          chaincode,
          depth,
          index,
          parentPublicKey,
        );

        // Derive the hierarchy of child keys.
        for (childIndex in pathArray.values()) {
          target := target.deriveChild(childIndex)!;
        };
        target;
      };
    };

    /// Derives a non-hardened child key at `index`.
    ///
    /// Never traps. Returns `null` when:
    /// - `index >= 2^31` (hardened indices cannot be derived from a public
    ///   key alone),
    /// - the HMAC-SHA512 left half is `≥` the secp256k1 group order (probability
    ///   under `2^-127`),
    /// - the parent key bytes do not represent a valid secp256k1 point, or
    /// - the resulting child point is the point at infinity (probability
    ///   under `2^-127`).
    // Derive child at the given index. Valid indices are in the range
    // [0, 2^31 - 1] and the function throws an error if given an index outside
    // this range.
    public func deriveChild(index : Nat32) : ?ExtendedPublicKey {
      if (isHardenedIndex(index)) {
        return null;
      };

      // Compute HMAC with chaincode as the key and the serialized
      // parentPublicKey (33 bytes) concatenated with the serialized
      // index (4 bytes) as its data.
      let hmacData : [var Nat8] = VarArray.repeat<Nat8>(0x00, 33 + 4);
      Common.copy(hmacData, 0, key, 0, 33);
      Common.writeBE32(hmacData, 33, index);
      let hmacSha512 : Hmac.Hmac = Hmac.sha512(chaincode);
      hmacSha512.writeArray(hmacData.toArray());
      let fullNode : [Nat8] = hmacSha512.sum().toArray();

      // Split HMAC output into two 32-byte sequences.
      let left : [Nat8] = Array.tabulate<Nat8>(
        32,
        func(i) {
          fullNode[i];
        },
      );
      let right : [Nat8] = Array.tabulate<Nat8>(
        32,
        func(i) {
          fullNode[i + 32];
        },
      );

      // Parse the left 32-bytes as an integer in the domain parameters of
      // secp2secp256k1 curve.
      let multiplicand : Nat = Common.readBE256(left, 0);
      if (multiplicand >= curve.r) {
        // This has probability lower than 1 in 2^127.
        return null;
      };

      switch (Jacobi.fromBytes(key, curve)) {
        case (null) {
          return null;
        };
        case (?parsedKey) {
          // Derive the child public key.
          switch (Jacobi.add(Jacobi.mulBase(multiplicand, curve), parsedKey)) {
            case (#infinity(_)) {
              return null;
            };
            case (childPublicKey) {
              return ?ExtendedPublicKey(
                Jacobi.toBytes(childPublicKey, true),
                right,
                depth + 1,
                index,
                ?(#publicKeyData key),
              );
            };
          };
        };
      };
    };

    /// Serializes this key to an `xpub` Base58Check string.
    ///
    /// The output follows the BIP32 extended public key wire format.
    ///
    /// Never traps when the instance was constructed with the canonical
    /// `33`-byte compressed key, `32`-byte chaincode, and `4`-byte
    /// fingerprint expected by BIP32. Constructing the instance with shorter
    /// arrays would cause out-of-bounds traps here.
    // Serialize the extended public key data into Base58 encoded string
    // following format dictated by BIP32 specification.
    public func serialize() : Text {
      let result = VarArray.repeat<Nat8>(0, 78);

      Common.writeBE32(result, 0, publicPrefix);

      switch (parentPublicKey) {
        case (null) {
          result[4] := 0x00;
          Common.writeBE64(result, 5, 0x00);
        };
        case (?(#publicKeyData parentPublicKey)) {
          result[4] := depth;
          let fingerprint = Hash.hash160(parentPublicKey);
          Common.copy(result, 5, fingerprint, 0, 4);
          Common.writeBE32(result, 9, index);
        };
        case (?(#fingerprint fingerprint)) {
          result[4] := depth;
          Common.copy(result, 5, fingerprint, 0, 4);
          Common.writeBE32(result, 9, index);
        };
      };
      Common.copy(result, 13, chaincode, 0, 32);
      Common.copy(result, 45, key, 0, key.size());

      Base58Check.encode(result.toArray());
    };
  };
};
