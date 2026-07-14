/// Bitcoin transaction input type and codec utilities.
///
/// ```motoko name=import
/// import TxInput "mo:bitcoin/bitcoin/TxInput";
/// ```

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import { type Iter; type Result } "mo:core/Types";
import VarArray "mo:core/VarArray";

import ByteUtils "../ByteUtils";
import Common "../Common";
import Script "Script";
import Types "Types";

module {
  /// Deserializes a transaction input from raw bytes.
  ///
  /// Never traps. Returns `#err(message)` when the byte stream is too short
  /// or the embedded script is malformed:
  /// - `"Could not read prevTxId."`,
  /// - `"Could not read prevTxOutputIndex."`,
  /// - `"Could not deserialize scriptSig: ..."` (propagated from
  ///   `Script.fromBytes`),
  /// - `"Could not read sequence."`.
  // Deserialize a TxInput  from bytes with layout:
  // | prevTxId | prevTx output index | script | sequence |
  public func fromBytes(data : Iter<Nat8>) : Result<TxInput, Text> {
    let (prevTxId, prevTxOutputIndex, script, sequence) = switch (
      ByteUtils.read(data, 32, false),
      ByteUtils.readLE32(data),
      Script.fromBytes(data, true),
      ByteUtils.readLE32(data),
    ) {
      case (?prevTxId, ?prevTxOutputIndex, #ok script, ?sequence) {
        (prevTxId.toBlob(), prevTxOutputIndex, script, sequence);
      };
      case (null, _, _, _) {
        return #err("Could not read prevTxId.");
      };
      case (_, null, _, _) {
        return #err("Could not read prevTxOutputIndex.");
      };
      case (_, _, #err(msg), _) {
        return #err("Could not deserialize scriptSig: " # msg);
      };
      case (_, _, _, null) {
        return #err("Could not read sequence.");
      };
    };

    let txIn = TxInput({ txid = prevTxId; vout = prevTxOutputIndex }, sequence);
    txIn.script := script;

    return #ok txIn;
  };

  /// Bitcoin transaction input.
  ///
  /// Constructor arguments:
  /// - `_prevOutput` — the previous transaction output being spent.
  /// - `_sequence` — the input sequence number. Use `0xffffffff` to
  ///   disable RBF/locktime semantics.
  ///
  /// `script` (the unlocking `scriptSig`) is initialized to the empty
  /// script and is mutated in place by the signing helpers.
  // Representation of a TxInput of a Bitcoin transaction. A TxInput is linked
  // to a previous transaction output given by prevOutput.
  public class TxInput(_prevOutput : Types.OutPoint, _sequence : Nat32) {

    /// Referenced previous output.
    public let prevOutput : Types.OutPoint = _prevOutput;
    /// Input sequence value.
    public let sequence : Nat32 = _sequence;
    // Unlocking script. This is mutuable to enable signature hash construction
    // for a transaction without having to clone the transaction.
    /// Unlocking script (`scriptSig`) for this input.
    public var script : Script.Script = [];

    /// Serializes this input using Bitcoin wire format.
    ///
    /// Traps if `script` has a `#data` element larger than `2^32 - 1` bytes
    /// (inherited from `Script.toBytes`).
    // Serialize to bytes with layout:
    // | prevTxId | prevTx output index | script | sequence |.
    public func toBytes() : [Nat8] {
      let encodedScript = Script.toBytes(script);
      // Total size based on output layout.
      let totalSize = 32 + 4 + encodedScript.size() + 4;
      let output = VarArray.repeat<Nat8>(0, totalSize);
      var outputOffset = 0;

      let prevTxId = prevOutput.txid.toArray();

      // Write prevTxId.
      Common.copy(output, outputOffset, prevTxId, 0, 32);
      outputOffset += 32;

      // Write prevTx output index.
      Common.writeLE32(output, outputOffset, prevOutput.vout);
      outputOffset += 4;

      // Write script.
      Common.copy(output, outputOffset, encodedScript, 0, encodedScript.size());
      outputOffset += encodedScript.size();

      // Write sequence.
      Common.writeLE32(output, outputOffset, sequence);
      outputOffset += 4;

      assert (outputOffset == output.size());
      output.toArray();
    };
  };
};
