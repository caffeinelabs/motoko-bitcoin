/// Shared Bitcoin types and constants.
///
/// ```motoko name=import
/// import Types "mo:bitcoin/bitcoin/Types";
/// ```

module {
  // A single unit of Bitcoin.
  /// Bitcoin amount denominated in satoshis (`1 BTC = 100_000_000`).
  public type Satoshi = Nat64;

  // The type of Bitcoin network.
  /// Supported Bitcoin networks.
  public type Network = {
    #Mainnet;
    #Regtest;
    #Testnet;
  };

  // A reference to a transaction output.
  /// Outpoint identifying a previous transaction output.
  ///
  /// `txid` is the 32-byte transaction hash in **serialization byte order**
  /// (the internal little-endian-ish order used inside transactions and
  /// block headers). This is the **reverse** of the byte order used in
  /// block explorers and JSON-RPC output — reverse the bytes before
  /// displaying or comparing against a user-supplied txid string.
  /// `vout` is the zero-based output index within that transaction.
  public type OutPoint = {
    txid : Blob;
    vout : Nat32;
  };

  // An unspent transaction output.
  /// Unspent transaction output (UTXO) data.
  ///
  /// `outpoint` references the funding transaction's output.
  /// `value` is the amount locked in the output, in satoshis.
  /// `height` is the block height at which the funding transaction was
  /// confirmed (`0` for unconfirmed UTXOs supplied by the caller).
  public type Utxo = {
    outpoint : OutPoint;
    value : Satoshi;
    height : Nat32;
  };

  /// Signature hash type bitfield.
  ///
  /// Combine the base mode (`SIGHASH_ALL`, `SIGHASH_NONE`,
  /// `SIGHASH_SINGLE`) with the optional `SIGHASH_ANYONECANPAY` flag
  /// using `or`. Encoded as the trailing byte appended to a DER signature.
  public type SighashType = Nat32;
  /// Sign all inputs and all outputs (the default).
  public let SIGHASH_ALL : SighashType = 0x01;
  /// Sign all inputs and no outputs.
  public let SIGHASH_NONE : SighashType = 0x02;
  /// Sign all inputs and only the output at the same index as the input.
  public let SIGHASH_SINGLE : SighashType = 0x03;
  /// OR-combine with one of the above to sign only the input being signed,
  /// allowing other inputs to be added or removed without invalidating it.
  public let SIGHASH_ANYONECANPAY : SighashType = 0x80;

  /// Decoded Bitcoin private key metadata.
  ///
  /// `network` is the network the WIF/key is for.
  /// `key` is the raw 256-bit secret scalar interpreted as a `Nat`
  ///   (must be in `[1, secp256k1_order)`).
  /// `compressedPublicKey` indicates whether the corresponding public key
  ///   should be encoded in SEC1 compressed form (33 bytes) rather than
  ///   uncompressed (65 bytes).
  public type BitcoinPrivateKey = {
    network : Network;
    key : Nat;
    compressedPublicKey : Bool;
  };

  /// Legacy Base58 P2PKH address string.
  public type P2PkhAddress = Text;
  /// SegWit v1 key-path (P2TR) address string.
  public type P2trKeyAddress = Text;
  /// SegWit v1 script-path (P2TR) address string.
  public type P2trScriptAddress = Text;

  /// Supported Bitcoin address variants.
  public type Address = {
    #p2pkh : P2PkhAddress;
    #p2tr_key : P2trKeyAddress;
    #p2tr_script : P2trScriptAddress;
  };
};
