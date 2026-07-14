/// Bitcoin transaction output type and codec utilities.
///
/// ```motoko name=import
/// import TxOutput "mo:bitcoin/bitcoin/TxOutput";
/// ```

import { type Iter; type Result } "mo:core/Types";
import VarArray "mo:core/VarArray";

import ByteUtils "../ByteUtils";
import Common "../Common";
import Script "Script";
import Types "Types";

module {
  /// Deserializes a transaction output from raw bytes.
  ///
  /// Never traps. Returns `#err(message)` when the byte stream is too short
  /// or the script is malformed:
  /// - `"Could not read TxOut amount"`,
  /// - `"Could not decode script: ..."` (propagated from `Script.fromBytes`).
  // Deserialize TxOutput from data with layout:
  // | amount | serialized script |
  public func fromBytes(data : Iter<Nat8>) : Result<TxOutput, Text> {
    switch (ByteUtils.readLE64(data), Script.fromBytes(data, true)) {
      case (?amount, #ok script) {
        #ok(TxOutput(amount, script));
      };
      case (?_amount, #err(msg)) {
        #err("Could not decode script: " # msg);
      };
      case (null, _) {
        #err "Could not read TxOut amount";
      };
    };
  };

  /// Bitcoin transaction output.
  // Representation of a TxOutput of a Bitcoin transaction. A TxOutput locks
  // specified amount of Satoshi with the given script.
  public class TxOutput(_amount : Types.Satoshi, _scriptPubKey : Script.Script) {

    /// Output amount in satoshis.
    public let amount : Types.Satoshi = _amount;
    /// Locking script (`scriptPubKey`).
    public let scriptPubKey : Script.Script = _scriptPubKey;

    /// Serializes this output using Bitcoin wire format.
    ///
    /// Traps if `scriptPubKey` has a `#data` element larger than `2^32 - 1`
    /// bytes (inherited from `Script.toBytes`).
    // Serialize to bytes with layout: | amount | serialized script |
    public func toBytes() : [Nat8] {
      let encodedScript = Script.toBytes(scriptPubKey);
      let totalSize = 8 + encodedScript.size();
      let output = VarArray.repeat<Nat8>(0, totalSize);

      Common.writeLE64(output, 0, amount);
      Common.copy(output, 8, encodedScript, 0, encodedScript.size());

      output.toArray();
    };
  };
};
