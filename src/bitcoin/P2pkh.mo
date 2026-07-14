/// P2PKH address and script helpers.
///
/// ```motoko name=import
/// import P2pkh "mo:bitcoin/bitcoin/P2pkh";
/// ```

import Array "mo:core/Array";
import { type Result; type Iter } "mo:core/Types";

import Base58 "../Base58";
import Base58Check "../Base58Check";
import ByteUtils "../ByteUtils";
import Hash "../Hash";
import Ecdsa "../ecdsa/Ecdsa";
import EcdsaTypes "../ecdsa/Types";
import Script "Script";
import Types "Types";

module {
  type PublicKey = Ecdsa.PublicKey;
  type Script = Script.Script;

  /// P2PKH address string type alias.
  ///
  /// A Base58Check string. Mainnet addresses start with `1`;
  /// testnet/regtest addresses start with `m` or `n`.
  public type Address = Types.P2PkhAddress;
  /// Decoded P2PKH components.
  ///
  /// `publicKeyHash` is the 20-byte HASH160 of the SEC1-encoded
  /// public key.
  public type DecodedAddress = {
    network : Types.Network;
    publicKeyHash : [Nat8];
  };

  /// Creates a standard P2PKH locking script from an address.
  ///
  /// Returns `#err(message)` propagated from `decodeAddress` (see that
  /// function for the exact error categories).
  public func makeScript(address : Address) : Result<Script, Text> {
    switch (decodeAddress(address)) {
      case (#ok { network = _; publicKeyHash }) {
        #ok([
          #opcode(#OP_DUP),
          #opcode(#OP_HASH160),
          #data(publicKeyHash),
          #opcode(#OP_EQUALVERIFY),
          #opcode(#OP_CHECKSIG),
        ]);
      };
      case (#err msg) {
        #err msg;
      };
    };
  };

  // Map given network to its id.
  func encodeVersion(network : Types.Network) : Nat8 {
    switch (network) {
      case (#Mainnet) {
        0x00;
      };
      case (#Regtest or #Testnet) {
        0x6f;
      };
    };
  };

  /// Derives a Base58Check P2PKH address from a SEC1 public key.
  ///
  /// Always returns a valid address (Base58Check string). Never traps for
  /// any `sec1PublicKey` input; the public-key bytes are hashed verbatim and
  /// no length validation is performed.
  public func deriveAddress(
    network : Types.Network,
    sec1PublicKey : EcdsaTypes.Sec1PublicKey,
  ) : Address {

    let (pkData, _) = sec1PublicKey;
    let ripemd160Hash : [Nat8] = Hash.hash160(pkData);
    let versionedHash : [Nat8] = Array.tabulate<Nat8>(
      ripemd160Hash.size() + 1,
      func(i) {
        if (i == 0) {
          encodeVersion(network);
        } else {
          ripemd160Hash[i - 1];
        };
      },
    );
    Base58Check.encode(versionedHash);
  };

  /// Decodes a P2PKH address into network and HASH160 payload.
  ///
  /// Returns `#err(message)` when:
  /// - `address` is not valid Base58Check (alphabet error or checksum
  ///   mismatch) — `"Could not base58 decode address."`,
  /// - the version byte is not `0x00` (mainnet) or `0x6f` (testnet/regtest)
  ///   — `"Unrecognized network id."`,
  /// - the decoded payload does not contain a version byte followed by
  ///   exactly 20 hash bytes — `"Could not decode address."`.
  public func decodeAddress(address : Address) : Result<DecodedAddress, Text> {

    if (not Base58.isBase58Alphabet(address)) {
      return #err("Could not base58 decode address.");
    };

    let decoded : Iter<Nat8> = switch (Base58Check.decode(address)) {
      case (?b58decoded) {
        b58decoded.values();
      };
      case _ {
        return #err("Could not base58 decode address.");
      };
    };

    return switch (decoded.next(), ByteUtils.read(decoded, 20, false)) {
      case (?(0x00), ?publicKeyHash) {
        #ok { network = #Mainnet; publicKeyHash = publicKeyHash };
      };
      case (?(0x6f), ?publicKeyHash) {
        #ok { network = #Testnet; publicKeyHash = publicKeyHash };
      };
      case (?(_networkId), ?_) {
        #err("Unrecognized network id.");
      };
      case _ {
        #err("Could not decode address.");
      };
    };
  };
};
