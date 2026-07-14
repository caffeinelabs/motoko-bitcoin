/// SegWit address encoding and decoding.
///
/// Implements conversion between witness programs and their Bech32/Bech32m
/// textual representation as defined in BIP173 and BIP350.
///
/// Import from the bitcoin package to use this module.
/// ```motoko name=import
/// import Segwit "mo:bitcoin/Segwit";
/// ```

import Array "mo:core/Array";
import Nat "mo:core/Nat";
import Nat16 "mo:core/Nat16";
import Nat32 "mo:core/Nat32";
import Nat8 "mo:core/Nat8";
import { type Result } "mo:core/Types";
import VarArray "mo:core/VarArray";

import Bech32 "Bech32";

module {

  /// A SegWit witness program.
  ///
  /// `version` is the witness version in `0..16` (`0` for P2WPKH/P2WSH,
  /// `1` for P2TR, etc.).
  /// `program` is the witness program bytes. Its length must be 2..40
  /// bytes; for `version = 0` it must be exactly 20 (P2WPKH) or 32 bytes
  /// (P2WSH).
  public type WitnessProgram = {
    version : Nat8;
    program : [Nat8];
  };

  /// Encodes a witness program as a SegWit address.
  ///
  /// `hrp` is the human-readable prefix that identifies the network
  /// (`"bc"` for mainnet, `"tb"` for testnet, `"bcrt"` for regtest).
  /// Uses Bech32 for witness version 0 and Bech32m for witness version >= 1.
  /// After encoding, the result is round-tripped through `decode` to verify
  /// it conforms to BIP173/BIP350.
  ///
  /// Example:
  /// ```motoko include=import
  /// let result = Segwit.encode("bc", {
  ///   version = 0;
  ///   program = [
  ///     0x75, 0x1e, 0x76, 0xe8, 0x19, 0x91, 0x96, 0xd4, 0x54, 0x94,
  ///     0x1c, 0x45, 0xd1, 0xb3, 0xa3, 0x23, 0xf1, 0x43, 0x3b, 0xd6,
  ///   ];
  /// });
  /// ```
  ///
  /// Returns `#err(message)` when the bit-group conversion of `program`
  /// fails (e.g. invalid padding) or when the round-trip `decode` rejects
  /// the produced address (size or version constraints violated).
  ///
  /// Traps if `hrp` is empty, contains characters outside `'!'`..`'~'`,
  /// contains uppercase letters, or if the resulting Bech32 string would
  /// exceed 90 characters — these are inherited from `Bech32.encode`.
  public func encode(hrp : Text, { version; program } : WitnessProgram) : Result<Text, Text> {

    if (version > 16) {
      return #err("Invalid witness version.");
    };

    let programSize = program.size();
    if (programSize < 2 or programSize > 40) {
      return #err("Wrong output size.");
    };

    if (version == 0 and programSize != 20 and programSize != 32) {
      return #err("Program size does not match witness version.");
    };

    let converted = switch (convertBits(program, 0, 8, 5, true)) {
      case (#err(msg)) return #err(msg);
      case (#ok(c)) c;
    };

    let encoding : Bech32.Encoding = if (version > 0) {
      #BECH32M;
    } else {
      #BECH32;
    };

    let bech32Result : Text = Bech32.encode(
      hrp,
      [[version] : [Nat8], converted].flatten(),
      encoding,
    );

    return switch (decode(bech32Result)) {
      case (#ok((decodedHrp, _))) {
        // if the following fails, then there is a bug in decoding
        assert hrp == decodedHrp;
        #ok(bech32Result);
      };
      case (#err(msg)) {
        #err(msg);
      };
    };
  };

  /// Decodes a SegWit address into `(hrp, witnessProgram)`.
  ///
  /// Validates witness version, witness program length, and Bech32/Bech32m
  /// compatibility with the witness version.
  ///
  /// Example:
  /// ```motoko include=import
  /// let decoded = Segwit.decode("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4");
  /// ```
  ///
  /// Never traps. Returns `#err(message)` with one of:
  /// - any error from `Bech32.decode` (invalid character, mixed casing,
  ///   bad separator, bad checksum, invalid HRP),
  /// - `"Invalid data length."` — the 5-bit-group payload is empty or
  ///   exceeds 65 groups,
  /// - `"Invalid witness version."` — the first group is `> 16`,
  /// - `"Wrong output size."` — the converted program is shorter than
  ///   2 or longer than 40 bytes,
  /// - `"Program size does not match witness version."` — a v0 program
  ///   that is not exactly 20 or 32 bytes,
  /// - `"Encoding does not match witness version."` — v0 with Bech32m
  ///   or v1+ with Bech32,
  /// - any error from the bit-group conversion (e.g. invalid padding).
  // Convert a segwit address into a human-readable part (HRP) and a Witness Program.
  // Decodes using Bech32.
  public func decode(address : Text) : Result<(Text, WitnessProgram), Text> {
    let (encoding, decodedHrp, data) = switch (Bech32.decode(address)) {
      case (#ok res) {
        res;
      };
      case (#err msg) {
        return #err(msg);
      };
    };

    if (data.size() == 0 or data.size() > 65) {
      return #err("Invalid data length.");
    };

    let version : Nat8 = data[0];

    if (version > 16) {
      return #err("Invalid witness version.");
    };

    let convertedData = switch (convertBits(data, 1, 5, 8, false)) {
      case (#err(msg)) return #err(msg);
      case (#ok(d)) d;
    };

    let convertedDataSize : Nat = convertedData.size();

    if (convertedDataSize < 2 or convertedDataSize > 40) {
      return #err("Wrong output size.");
    };

    if (
      version == 0 and convertedDataSize != 20 and convertedDataSize != 32
    ) {
      return #err("Program size does not match witness version.");
    };

    if (
      version == 0 and encoding != #BECH32 or
      version != 0 and encoding != #BECH32M
    ) {
      return #err("Encoding does not match witness version.");
    };

    #ok(decodedHrp, { version; program = convertedData });
  };

  // Convert between two bases that are power of 2.
  func convertBits(
    data : [Nat8],
    start : Nat,
    from : Nat32,
    to : Nat32,
    pad : Bool,
  ) : Result<[Nat8], Text> {

    var acc : Nat32 = 0;
    var bits : Nat32 = 0;
    let maxv : Nat32 = (1 << to) - 1;
    let dataSize = data.size();
    let output = VarArray.repeat<Nat8>(0, (dataSize - start) * from.toNat() / to.toNat() + 1);
    var outputLen : Nat = 0;

    var pos = start;
    while (pos < dataSize) {
      let v : Nat32 = data[pos].toNat16().toNat32();

      if ((v >> from) != 0) {
        return #err("Invalid input value: " # data[pos].toNat().toText());
      };

      acc := (acc << from) | v;
      bits += from;

      while (bits >= to) {
        bits -= to;
        output[outputLen] := ((acc >> bits) & maxv).toNat16().toNat8();
        outputLen += 1;
      };
      pos += 1;
    };

    if (pad) {
      if (bits > 0) {
        output[outputLen] := ((acc << (to - bits)) & maxv).toNat16().toNat8();
        outputLen += 1;
      };
    } else if (bits >= from or ((acc << (to - bits)) & maxv) != 0) {
      return #err("Invalid Padding");
    };

    #ok(Array.tabulate<Nat8>(outputLen, func(i) = output[i]));
  };
};
