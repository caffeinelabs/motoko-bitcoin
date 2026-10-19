/// HMAC (Hash-based Message Authentication Code) implementation.
///
/// Supports HMAC-SHA256 and HMAC-SHA512, used in BIP32 key derivation
/// and other Bitcoin cryptographic operations.
///
/// Import from the bitcoin package to use this module.
/// ```motoko name=import
/// import Hmac "mo:bitcoin/Hmac";
/// ```

import Array "mo:core/Array";
import Blob "mo:core/Blob";

import Sha256 "mo:sha2/Sha256";
import Sha512 "mo:sha2/Sha512";

module {
  /// Interface for an incremental hash digest.
  ///
  /// Allows writing data in chunks and retrieving the final hash.
  public type Digest = {
    writeArray : ([Nat8]) -> ();
    sum : () -> Blob;
  };

  /// Factory for creating `Digest` instances of a specific hash function.
  ///
  /// `blockSize` is the internal block size in bytes (64 for SHA256, 128 for SHA512).
  /// `create` returns a fresh `Digest` instance.
  public type DigestFactory = {
    blockSize : Nat;
    create : () -> Digest;
  };

  /// HMAC instance for computing an incremental HMAC.
  ///
  /// Allows writing data in chunks and retrieving the final HMAC.
  ///
  /// NOTE: An Hmac is one-shot. Calling `sum()` finalizes and consumes the
  /// instance: `closed` is set, and any subsequent call to `sum()` or
  /// `writeArray()` will trap. To compute another HMAC, construct a new Hmac.
  public type Hmac = {
    writeArray : ([Nat8]) -> ();
    sum : () -> Blob;
  };

  object sha256DigestFactory {
    public let blockSize : Nat = 64;
    public func create() : Digest {
      let digest = Sha256.new(#sha256);
      {
        writeArray = func(data : [Nat8]) = digest.writeArray(data);
        sum = func() : Blob = digest.sum();
      };
    };
  };
  /// Creates an HMAC-SHA256 instance with the given `key`.
  ///
  /// Example:
  /// ```motoko include=import
  /// let hmac = Hmac.sha256([0x01, 0x02, 0x03]);
  /// hmac.writeArray([0x04, 0x05]);
  /// let result = hmac.sum();
  /// ```
  ///
  /// Never traps. Accepts a `key` of any length, including the empty key.
  /// `writeArray` and `sum` do not trap on any input, but the instance is
  /// one-shot: after `sum()` locks it, further `writeArray`/`sum` calls trap.
  // Sha256 support.
  public func sha256(key : [Nat8]) : Hmac = HmacImpl(key, sha256DigestFactory);

  object sha512DigestFactory {
    public let blockSize : Nat = 128;
    public func create() : Digest {
      let digest = Sha512.new(#sha512);
      {
        writeArray = func(data : [Nat8]) = digest.writeArray(data);
        sum = func() : Blob = digest.sum();
      };
    };
  };
  /// Creates an HMAC-SHA512 instance with the given `key`.
  ///
  /// Example:
  /// ```motoko include=import
  /// let hmac = Hmac.sha512([0x01, 0x02, 0x03]);
  /// hmac.writeArray([0x04, 0x05]);
  /// let result = hmac.sum();
  /// ```
  ///
  /// Never traps. Accepts a `key` of any length, including the empty key.
  /// `writeArray` and `sum` do not trap on any input, but the instance is
  /// one-shot: after `sum()` locks it, further `writeArray`/`sum` calls trap.
  // Sha512 support.
  public func sha512(key : [Nat8]) : Hmac = HmacImpl(key, sha512DigestFactory);

  /// Creates an HMAC instance using a custom digest factory.
  ///
  /// Use this when neither SHA256 nor SHA512 matches your needs.
  ///
  /// Example:
  /// ```motoko include=import
  /// // Use a custom digest factory
  /// // let hmac = Hmac.new(key, myFactory);
  /// ```
  ///
  /// Never traps as long as the supplied `digestFactory` itself is total.
  /// Trap behavior of `writeArray` and `sum` on the returned instance is
  /// inherited from the digest implementation.
  // Construct HMAC from an arbitrary digest function.
  public func new(key : [Nat8], digestFactory : DigestFactory) : Hmac {
    HmacImpl(key, digestFactory);
  };

  // Construct HMAC from the given digest function:
  // HMAC(key, data) = H((key' ^ outerPad) || H((key' ^ innerPad) || data))
  // key' = H(key) if key larger than block size, otherwise equals key
  // H is a cryptographic hash function
  class HmacImpl(key : [Nat8], digestFactory : DigestFactory) : Hmac {
    let innerDigest : Digest = digestFactory.create();
    let outerDigest : Digest = digestFactory.create();
    let innerPad : Nat8 = 0x36;
    let outerPad : Nat8 = 0x5c;
    var closed = false;

    do {
      let blockSize = digestFactory.blockSize;
      let blockSizedKey : [Nat8] = if (key.size() <= blockSize) {
        // key' = key + [0x00] * (blockSize - key.size())
        Array.tabulate<Nat8>(
          blockSize,
          func(i) {
            if (i < key.size()) {
              key[i];
            } else {
              0;
            };
          },
        );
      } else {
        // key' = H(key) + [0x00] * (blockSize - key.size())
        let keyDigest : Digest = digestFactory.create();
        keyDigest.writeArray(key);
        let keyHash = keyDigest.sum().toArray();

        Array.tabulate<Nat8>(
          blockSize,
          func(i) {
            if (i < keyHash.size()) {
              keyHash[i];
            } else {
              0;
            };
          },
        );
      };

      // H(key' ^ outerPad)
      let outerPaddedKey = blockSizedKey.map<Nat8, Nat8>(
        func(byte) {
          byte ^ outerPad;
        }
      );
      outerDigest.writeArray(outerPaddedKey);

      // H(key' ^ innerPad)
      let innerPaddedKey = blockSizedKey.map<Nat8, Nat8>(
        func(byte) {
          byte ^ innerPad;
        }
      );
      innerDigest.writeArray(innerPaddedKey);
    };

    public func writeArray(data : [Nat8]) {
      assert (not closed);
      innerDigest.writeArray(data);
    };

    public func sum() : Blob {
      assert (not closed);
      closed := true;
      let innerHash = innerDigest.sum().toArray();
      outerDigest.writeArray(innerHash);
      outerDigest.sum();
    };
  };
};
