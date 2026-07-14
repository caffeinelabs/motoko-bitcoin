/// High-level Bitcoin transaction construction and signing helpers.
///
/// This module focuses on P2PKH transaction flows using provided UTXOs,
/// destination outputs, and an abstract ECDSA signing proxy.
///
/// ```motoko name=import
/// import Bitcoin "mo:bitcoin/bitcoin/Bitcoin";
/// ```

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import List "mo:core/List";
import Nat "mo:core/Nat";
import Nat16 "mo:core/Nat16";
import Nat32 "mo:core/Nat32";
import Nat8 "mo:core/Nat8";
import { type Result } "mo:core/Types";
import VarArray "mo:core/VarArray";

import Der "../ecdsa/Der";
import Address "Address";
import Script "Script";
import Transaction "Transaction";
import TxInput "TxInput";
import TxOutput "TxOutput";
import Types "Types";
import Witness "Witness";

module {
  type Utxo = Types.Utxo;
  type Satoshi = Types.Satoshi;
  type OutPoint = Types.OutPoint;

  let dustThreshold : Satoshi = 10_000;
  let defaultSequence : Nat32 = 0xffffffff;

  /// Interface for an external ECDSA signing service (typically the
  /// Internet Computer's threshold-ECDSA management canister).
  ///
  /// `sign(messageHash, derivationPath)` takes a 32-byte message hash and
  /// a BIP32 derivation path (each path component encoded as a `Blob`)
  /// and must return a 64-byte signature: the big-endian `r` (32 bytes)
  /// concatenated with the big-endian `s` (32 bytes).
  ///
  /// `publicKey()` must return `(sec1Pubkey, chainCode)` where `sec1Pubkey`
  /// is the SEC1-encoded public key (33 bytes compressed or 65 bytes
  /// uncompressed) corresponding to `derivationPath = []` (i.e. the root
  /// public key), and `chainCode` is the 32-byte chain code.
  public type EcdsaProxy = {
    sign : (Blob, [Blob]) -> Blob;
    publicKey : () -> (Blob, Blob);
  };

  /// Builds an unsigned transaction from UTXOs and destination outputs.
  ///
  /// Selects UTXOs in the order given by `utxos` until the sum covers
  /// `fees + sum(destinations)`. Adds a change output to `changeAddress`
  /// when the leftover exceeds the dust threshold (10_000 satoshis).
  ///
  /// Never traps. Returns `#err(message)` when:
  /// - `version` is not `1` or `2`
  ///   (`"Unexpected version number: ..."`),
  /// - any destination or `changeAddress` cannot be converted to a
  ///   `scriptPubKey` (errors propagated from `Address.scriptPubKey`),
  /// - the supplied `utxos` cannot cover `fees + sum(destinations)`
  ///   (`"Insufficient balance"`).
  // Builds a transaction.
  // `version` is the transaction version. Currently only 1 and 2 are
  // supported.
  // `utxos` is a set of unspent transaction outputs to construct TxInputs from.
  // `destinations` is a list of address-value pairs indicating the amount to
  // transfer to each address.
  // `changeAddress` is an address to return any remaining amount to.
  // `fees` indicate the transaction fees.
  public func buildTransaction(
    version : Nat32,
    utxos : [Utxo],
    destinations : [(Types.Address, Satoshi)],
    changeAddress : Types.Address,
    fees : Satoshi,
  ) : Result<Transaction.Transaction, Text> {

    if (version != 1 and version != 2) {
      return #err("Unexpected version number: " # version.toText());
    };

    // Collect TxOutputs, making space for a potential extra output for change.
    let txOutputs = List.empty<TxOutput.TxOutput>();
    var totalSpend : Satoshi = fees;

    for (dest in destinations.values()) {
      let (destAddr, destAmount) = dest;
      switch (Address.scriptPubKey(destAddr)) {
        case (#ok destScriptPubKey) {
          txOutputs.add(TxOutput.TxOutput(destAmount, destScriptPubKey));
          totalSpend += destAmount;
        };
        case (#err msg) {
          return #err msg;
        };
      };
    };

    // Select which UTXOs to spend. For now, we spend the first available
    // UTXOs.
    var availableFunds : Satoshi = 0;
    let txInputs = List.empty<TxInput.TxInput>();

    label UtxoLoop for (utxo in utxos.values()) {
      availableFunds += utxo.value;
      txInputs.add(TxInput.TxInput(utxo.outpoint, defaultSequence));

      if (availableFunds >= totalSpend) {
        // We have enough inputs to cover the amount we want to spend.
        break UtxoLoop;
      };
    };

    if (availableFunds < totalSpend) {
      return #err "Insufficient balance";
    };

    // If there is remaining amount that is worth considering then include a
    // change TxOutput.
    let remainingAmount : Satoshi = availableFunds - totalSpend;

    if (remainingAmount > dustThreshold) {
      switch (Address.scriptPubKey(changeAddress)) {
        case (#ok chScriptPubKey) {
          txOutputs.add(TxOutput.TxOutput(remainingAmount, chScriptPubKey));
        };
        case (#err msg) {
          return #err msg;
        };
      };
    };

    return #ok(
      Transaction.Transaction(
        version,
        txInputs.toArray(),
        txOutputs.toArray(),
        VarArray.repeat<Witness.Witness>(Witness.EMPTY_WITNESS, txInputs.size()),
        0,
      )
    );
  };

  /// Signs all inputs of a P2PKH transaction.
  ///
  /// Computes the SIGHASH_ALL signature hash for each input, asks
  /// `ecdsaProxy` for a signature, DER-encodes it, appends the sighash type
  /// byte, and stores the resulting `<sig> <pubkey>` scriptSig on each input.
  /// Mutates `transaction.txInputs[i].script` in place.
  ///
  /// Returns `#err(message)` when `Address.scriptPubKey(sourceAddress)`
  /// fails. Otherwise returns `#ok(transaction)`.
  ///
  /// Traps if `transaction.txInputs` is non-empty and the supplied
  /// `ecdsaProxy.sign` returns a signature blob that cannot be DER-encoded
  /// by `Der.encodeSignature` (in practice this requires a signature blob
  /// other than the expected 64-byte concatenation of `r` and `s`).
  // Sign given transaction.
  // `sourceAddress` is the spender's address appearing in the TxOutputs being
  // spent from.
  // `ecdsaProxy` is an interface providing ecdsa signing functionality.
  public func signP2pkhTransaction(
    sourceAddress : Types.Address,
    transaction : Transaction.Transaction,
    ecdsaProxy : EcdsaProxy,
    derivationPath : [Blob],
  ) : Result<Transaction.Transaction, Text> {

    // Obtain the scriptPubKey of the source address which is also the
    // scriptPubKey of the Tx output being spent.
    switch (Address.scriptPubKey(sourceAddress)) {
      case (#ok scriptPubKey) {
        // Obtain scriptSigs for each Tx input.
        let scriptSigs = Array.tabulate<Script.Script>(
          transaction.txInputs.size(),
          func(i) {
            let sighash : [Nat8] = transaction.createP2pkhSignatureHash(
              scriptPubKey,
              Nat32.fromIntWrap(i),
              Types.SIGHASH_ALL,
            );
            let signature : Blob = ecdsaProxy.sign(
              sighash.toBlob(),
              derivationPath,
            );
            let encodedSignature : [Nat8] = Der.encodeSignature(signature).toArray();
            // Append the sighash type.
            let encodedSignatureWithSighashType = Array.tabulate<Nat8>(
              encodedSignature.size() + 1,
              func(n) {
                if (n < encodedSignature.size()) {
                  encodedSignature[n];
                } else {
                  Types.SIGHASH_ALL.toNat16().toNat8();
                };
              },
            );

            // Create Script Sig which looks like:
            // ScriptSig = <Signature> <Public Key>.
            [
              #data encodedSignatureWithSighashType,
              #data(ecdsaProxy.publicKey().0.toArray()),
            ];
          },
        );
        // Assign ScriptSigs to their associated TxInputs.
        for (i in Nat.range(0, scriptSigs.size())) {
          transaction.txInputs[i].script := scriptSigs[i];
        };

        #ok transaction;
      };
      case (#err msg) {
        #err msg;
      };
    };
  };

  /// Builds and signs a P2PKH transaction in one step.
  ///
  /// Equivalent to calling `buildTransaction` followed by
  /// `signP2pkhTransaction`. Returns `#err(message)` propagated from either
  /// step (see those functions for the full list of error and trap
  /// conditions).
  // `sourceAddress` is the spender's address appearing in the TxOutputs being
  // spent from.
  // `ecdsaProxy` is an interface for ECDSA signing functionality.
  // `version` is the transaction version. Currently only 1 and 2 are
  // supported.
  // `utxos` is a set of unspent transaction outputs to construct TxInputs from.
  // `destinations` is a list of address-value pairs indicating the amount to
  // transfer to each address.
  // `changeAddress` is an address to return any remaining amount to.
  // `fees` indicate the transaction fees.
  public func createSignedP2pkhTransaction(
    sourceAddress : Types.Address,
    ecdsaProxy : EcdsaProxy,
    derivationPath : [Blob],
    version : Nat32,
    utxos : [Utxo],
    destinations : [(Types.Address, Satoshi)],
    changeAddress : Types.Address,
    fees : Satoshi,
  ) : Result<Transaction.Transaction, Text> {

    switch (
      buildTransaction(
        version,
        utxos,
        destinations,
        changeAddress,
        fees,
      )
    ) {
      case (#ok transaction) {
        signP2pkhTransaction(sourceAddress, transaction, ecdsaProxy, derivationPath);
      };
      case (#err msg) {
        #err msg;
      };
    };
  };
};
