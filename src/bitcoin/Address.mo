/// Bitcoin address helpers.
///
/// Provides parsing, script generation, and equality checks for supported
/// Bitcoin address variants.
///
/// ```motoko name=import
/// import Address "mo:bitcoin/bitcoin/Address";
/// ```

import { type Result } "mo:core/Types";

import Segwit "../Segwit";
import P2pkh "P2pkh";
import P2tr "P2tr";
import Script "Script";
import Types "Types";

module {
  /// Parses textual address data into a typed address variant.
  ///
  /// First tries SegWit (Bech32/Bech32m) decoding. If that fails, falls back
  /// to P2PKH (Base58Check) decoding.
  ///
  /// Note: any successfully decoded SegWit address is returned as
  /// `#p2tr_key(address)`, regardless of the actual witness version
  /// (P2WPKH, P2WSH, and P2TR all collapse to the same variant). Inspect
  /// the address text or call `Segwit.decode` directly if you need to
  /// distinguish them.
  ///
  /// Returns `#err("Failed to decode address ...")` when the
  /// input is neither a valid SegWit nor a valid P2PKH address.
  public func addressFromText(address : Text) : Result<Types.Address, Text> {
    switch (Segwit.decode(address)) {
      case (#ok _) {
        return #ok(#p2tr_key(address));
      };
      case (_) {};
    };

    switch (P2pkh.decodeAddress(address)) {
      case (#ok _) {
        return #ok(#p2pkh(address));
      };
      case (_) {};
    };

    #err("Failed to decode address " # address);
  };

  /// Builds the locking script (`scriptPubKey`) for a given address.
  ///
  /// Never traps. Returns `#err(...)` when:
  /// - `address` is `#p2tr_script`, which is not yet supported (returns
  ///   `#err("Calling scriptPubKey on an unknown address type")`).
  /// - The underlying `P2pkh.makeScript` or
  ///   `P2tr.makeScriptFromP2trKeyAddress` call fails (e.g. malformed
  ///   address text).
  public func scriptPubKey(
    address : Types.Address
  ) : Result<Script.Script, Text> {
    switch (address) {
      case (#p2pkh p2pkhAddr) {
        return P2pkh.makeScript(p2pkhAddr);
      };
      case (#p2tr_key p2trKeyAddr) {
        P2tr.makeScriptFromP2trKeyAddress(p2trKeyAddr);
      };
      case (_) {
        return #err "Calling scriptPubKey on an unknown address type";
      };
    };
  };

  /// Compares two addresses for value equality.
  ///
  /// Two addresses are considered equal only when they have the same variant
  /// and the same underlying text. Cross-variant comparisons (e.g. P2PKH
  /// against P2TR) always return `false`, even if the keys are related.
  /// Never traps.
  public func isEqual(
    address1 : Types.Address,
    address2 : Types.Address,
  ) : Bool {
    switch (address1, address2) {
      case (#p2pkh address1, #p2pkh address2) {
        address1 == address2;
      };
      case (#p2tr_key address1, #p2tr_key address2) {
        address1 == address2;
      };
      case (#p2tr_script address1, #p2tr_script address2) {
        address1 == address2;
      };
      case (_) {
        false;
      };
    };
  };
};
