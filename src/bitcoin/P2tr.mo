/// Taproot (P2TR) address and tweak helpers.
///
/// ```motoko name=import
/// import P2tr "mo:bitcoin/bitcoin/P2tr";
/// ```

import Array "mo:core/Array";
import Nat "mo:core/Nat";
import { type Result } "mo:core/Types";

import Common "../Common";
import Hash "../Hash";
import Segwit "../Segwit";
import Curves "../ec/Curves";
import Fp "../ec/Fp";
import Jacobi "../ec/Jacobi";
import Script "Script";
import Types "Types";

module {
  type PublicKey = {
    bip340_public_key : [Nat8];
    is_even : Bool;
  };
  type Script = Script.Script;

  /// P2TR key-path address string alias.
  public type P2trKeyAddress = Types.P2trKeyAddress;
  /// Decoded P2TR address payload.
  public type DecodedAddress = {
    network : Types.Network;
    publicKeyHash : [Nat8];
  };

  /// Create script for the given P2TR key spend address (see
  /// [BIP341](https://github.com/bitcoin/bips/blob/master/bip-0341.mediawiki)
  /// for more details).
  ///
  /// Never traps. Returns `#err(message)` propagated from `Segwit.decode`
  /// when `address` is not a valid SegWit string.
  public func makeScriptFromP2trKeyAddress(address : P2trKeyAddress) : Result<Script, Text> {
    switch (Segwit.decode(address)) {
      case (#ok(_, { version = _; program })) {
        #ok([
          #opcode(#OP_1),
          // #opcode(#OP_PUSHBYTES_32) is implicit and added by the
          // #data below
          #data(program),
        ]);
      };
      case (#err msg) {
        #err msg;
      };
    };
  };

  /// Creates a tapscript leaf script from a BIP340 public key.
  ///
  /// Never traps. Returns
  /// `#err("Invalid BIP-340 public key length: expected 32 but got N")`
  /// when `bip340_spender_public_key.size() != 32`.
  public func leafScript(bip340_spender_public_key : [Nat8]) : Result<Script, Text> {
    if (bip340_spender_public_key.size() != 32) {
      return #err("Invalid BIP-340 public key length: expected 32 but got " # bip340_spender_public_key.size().toText());
    };
    #ok([
      // #opcode(#OP_PUSHBYTES_32) is implicit and added by the
      // #data below
      #data(bip340_spender_public_key),
      #opcode(#OP_CHECKSIG),
    ]);
  };

  /// Computes the TapLeaf hash for a leaf script.
  ///
  /// Traps if any `#data` element of `leaf_script` is larger than `2^32 - 1`
  /// bytes (inherited from `Script.toBytes`). For scripts produced by this
  /// module that limit is never reached in practice.
  public func leafHash(leaf_script : Script.Script) : [Nat8] {
    // BIP-342 tapscript
    let TAPROOT_LEAF_TAPSCRIPT : [Nat8] = [0xc0];
    let script_bytes = Script.toBytes(leaf_script);
    Hash.taggedHash([TAPROOT_LEAF_TAPSCRIPT, script_bytes].flatten(), "TapLeaf");
  };

  /// Computes a tweak from the internal key and a hash. Corresponds to
  /// ```python
  ///     t = int_from_bytes(tagged_hash("TapTweak", pubkey + h))
  ///     if t >= SECP256K1_ORDER:
  ///         raise ValueError
  /// ```
  /// in `taproot_tweak_pubkey` function in
  /// [BIP341](https://github.com/bitcoin/bips/blob/master/bip-0341.mediawiki).
  ///
  /// Never traps. Returns `#err(message)` when:
  /// - `internal_key.size() != 32`,
  /// - `hash.size() != 32`, or
  /// - the tagged hash interpreted as a big-endian integer is `≥` the
  ///   secp256k1 field prime (probability under `2^-128`).
  public func tweakFromKeyAndHash(internal_key : [Nat8], hash : [Nat8]) : Result<Fp.Fp, Text> {
    if (internal_key.size() != 32) {
      return #err("Failed to compute tweak, invalid internal key length: expected 32 but got " # internal_key.size().toText());
    } else if (hash.size() != 32) {
      return #err("Failed to compute tweak, invalid hash length: expected 32 but got " # hash.size().toText());
    };

    let tagged_hash = Hash.taggedHash([internal_key, hash].flatten(), "TapTweak");

    let tweak = Common.readBE256(tagged_hash, 0);

    if (tweak >= Curves.secp256k1.p) {
      return #err("Failed to compute tweak, tweak is not smaller than the field prime");
    };

    #ok(Curves.secp256k1.Fp(tweak));
  };

  /// Corresponds to
  /// ```python
  ///     P = lift_x(int_from_bytes(pubkey))
  ///     if P is None:
  ///         raise ValueError
  ///     Q = point_add(P, point_mul(G, t))
  ///     return 0 if has_even_y(Q) else 1, bytes_from_int(x(Q))
  /// ```
  /// `taproot_tweak_pubkey` function in
  /// [BIP341](https://github.com/bitcoin/bips/blob/master/bip-0341.mediawiki).
  ///
  /// Never traps. Returns `#err("Failed to tweak public key, invalid public key")`
  /// when `public_key_bip340_bytes` does not encode a valid x-only point on
  /// secp256k1, or the lifted point is the point at infinity. Returns
  /// `#err("Tweaking produced an invalid public key")` when the tweaked
  /// point is at infinity (probability under `2^-128`).
  public func tweakPublicKey(public_key_bip340_bytes : [Nat8], tweak : Fp.Fp) : Result<PublicKey, Text> {
    let even_point_flag : [Nat8] = [0x02];
    let public_key_sec1_bytes = [even_point_flag, public_key_bip340_bytes].flatten();
    let public_key_point = switch (Jacobi.fromBytes(public_key_sec1_bytes, Curves.secp256k1)) {
      case (?point) {
        switch (point) {
          case (#infinity _) {
            return #err("Failed to tweak public key, invalid public key");
          };
          case (_) {};
        };
        point;
      };
      case (null) {
        return #err("Failed to tweak public key, invalid public key");
      };
    };

    let tweak_point = Jacobi.mulBase(tweak.value, Curves.secp256k1);

    let tweaked_public_key = Jacobi.add(public_key_point, tweak_point);

    if (not Jacobi.isOnCurve(tweaked_public_key) or Jacobi.isInfinity(tweaked_public_key)) {
      return #err("Tweaking produced an invalid public key");
    };

    let tweaked_public_key_sec1_bytes = Jacobi.toBytes(tweaked_public_key, true);
    #ok({
      bip340_public_key = tweaked_public_key_sec1_bytes.sliceToArray(1, 33);
      is_even = tweaked_public_key_sec1_bytes[0] == 0x02;
    });
  };
};
