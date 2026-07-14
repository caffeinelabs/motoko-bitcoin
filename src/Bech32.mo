/// Bech32 and Bech32m encoding and decoding.
///
/// Bech32 is a segwit address format defined in
/// [BIP173](https://github.com/bitcoin/bips/blob/master/bip-0173.mediawiki).
/// Bech32m is a modification defined in
/// [BIP350](https://github.com/bitcoin/bips/blob/master/bip-0350.mediawiki)
/// used for native segwit version 1 (Taproot) and later addresses.
///
/// Import from the bitcoin package to use this module.
/// ```motoko name=import
/// import Bech32 "mo:bitcoin/Bech32";
/// ```

import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Nat "mo:core/Nat";
import Nat16 "mo:core/Nat16";
import Nat32 "mo:core/Nat32";
import Nat8 "mo:core/Nat8";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";
import { type Result } "mo:core/Types";
import VarArray "mo:core/VarArray";

module {
  /// The Bech32 encoding variant to use.
  ///
  /// - `#BECH32`: Original Bech32 encoding (BIP173), used for segwit version 0.
  /// - `#BECH32M`: Bech32m encoding (BIP350), used for segwit version 1+.
  public type Encoding = {
    #BECH32;
    #BECH32M;
  };

  /// The result of a successful Bech32 decode operation.
  ///
  /// Contains the encoding type, the human-readable part (HRP), and the data
  /// payload as a byte array.
  // A decoded result contains Encoding type, human-readable part (HRP), and Data.
  public type DecodeResult = (Encoding, Text, [Nat8]);

  let CHAR_a : Nat8 = 0x61;
  let CHAR_A : Nat8 = 0x41;
  let CHAR_z : Nat8 = 0x7a;
  let CHAR_Z : Nat8 = 0x5a;
  let CHAR_1 : Nat8 = 0x31;
  // Code for '!'.
  let CHARS_LOWLIMIT : Nat8 = 0x21;
  // Code for '~'.
  let CHARS_HIGHLIMIT : Nat8 = 0x7e;

  // prettier-ignore
  let charset : [Nat8] = [
    0x71, 0x70, 0x7a, 0x72, 0x79, 0x39, 0x78, 0x38, 0x67, 0x66, 0x32, 0x74, 0x76, 0x64, 0x77,
    0x30, 0x73, 0x33, 0x6a, 0x6e, 0x35, 0x34, 0x6b, 0x68, 0x63, 0x65, 0x36, 0x6d, 0x75, 0x61,
    0x37, 0x6c
  ];

  // Mapping from ASCII to indices in charset for characters that exist in
  // charset. 255 is treated as a non-valid index.
  // prettier-ignore
  let reverseCharset : [Nat8] = [
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255,
    255, 255, 255, 15, 255, 10, 17, 21, 20, 26, 30,  7,  5, 255, 255, 255, 255,
    255, 255, 255, 29, 255, 24, 13, 25,  9,  8, 23, 255, 18, 22, 31, 27, 19,
    255, 1,  0,  3, 16, 11, 28, 12, 14,  6,  4,  2, 255, 255, 255, 255, 255,
    255, 29, 255, 24, 13, 25,  9,  8, 23, 255, 18, 22, 31, 27, 19, 255, 1,  0,
    3, 16, 11, 28, 12, 14,  6,  4,  2, 255, 255, 255, 255, 255
  ];

  func arrayToText(arr : [Nat8]) : Text {
    switch (arr.toBlob().decodeUtf8()) {
      case (?t) t;
      case null Runtime.trap("unreachable");
    };
  };

  /// Encodes data as a Bech32 or Bech32m string.
  ///
  /// `hrp` is the human-readable part (must be lowercase ASCII in the range
  /// `'!'`..`'~'` and non-empty). `values` is the data payload encoded as
  /// 5-bit groups (each value must be in `[0, 31]`). `encoding` selects
  /// between `#BECH32` (BIP173, segwit v0) and `#BECH32M` (BIP350,
  /// segwit v1+).
  ///
  /// Example:
  /// ```motoko include=import
  /// let encoded = Bech32.encode("bc", [0, 1, 2], #BECH32M);
  /// ```
  ///
  /// Traps if any of the following hold:
  /// - `hrp` is empty.
  /// - `hrp` contains a character outside the printable ASCII range
  ///   `'!'`..`'~'`, or contains an uppercase letter `'A'`..`'Z'`.
  /// - Any byte in `values` is greater than `31` (out-of-bounds index into
  ///   the Bech32 charset).
  /// - The encoded output would exceed the 90-character Bech32 limit.
  // Encode input in Bech32 or a Bech32m.
  public func encode(hrp : Text, values : [Nat8], encoding : Encoding) : Text {
    assert hrp.size() > 0;

    // Ensure HRP is lowercase.
    for (c in hrp.chars()) {
      assert (c <= '~' and c >= '!' and not (c <= 'Z' and c >= 'A'));
    };

    // Calculate checksum
    let encodedHrp : [Nat8] = hrp.encodeUtf8().toArray();
    let checksum : [Nat8] = createChecksum(encodedHrp, values, encoding);

    // hrp | '1' | values | checksum.
    let output : [Nat8] = [
      encodedHrp,
      [0x31] : [Nat8],
      values.map(func x = charset[x.toNat()]),
      checksum.map(func x = charset[x.toNat()]),
    ].flatten();

    assert output.size() <= 90;

    arrayToText(output);
  };

  /// Decodes a Bech32 or Bech32m encoded string.
  ///
  /// Returns `#ok((encoding, hrp, data))` on success. The `hrp` in the
  /// result is normalized to lowercase and `data` is the 5-bit-group
  /// payload (excluding checksum).
  ///
  /// Example:
  /// ```motoko include=import
  /// let result = Bech32.decode("bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4");
  /// ```
  ///
  /// Never traps. Returns `#err(message)` for every malformed input. The
  /// distinct error categories are:
  /// - `"Found unexpected character: ..."` — `input` contains a byte
  ///   outside the printable ASCII range `'!'`..`'~'`.
  /// - `"Inconsistent character casing in HRP."` — `input` contains both
  ///   lowercase and uppercase alphabetic characters (forbidden by Bech32
  ///   standard).
  /// - `"Bad separator position: ..."` — the `'1'` separator is missing,
  ///   too close to the start, or leaves fewer than 6 checksum characters
  ///   at the end; or the total length exceeds 90 characters.
  /// - `"Invalid character found: ..."` — a character in the data section
  ///   is not part of the Bech32 charset.
  /// - `"Checksum verification failed."` — the polymod checksum (computed
  ///   for both BECH32 and BECH32M) does not match either variant.
  /// - `"Failed to decode HRP."` — the HRP bytes are not valid UTF-8.
  // Decode given text as Bech32 or Bech32m.
  public func decode(input : Text) : Result<DecodeResult, Text> {
    // Locate the '1' separator.
    var separatorIndex : Nat = 0;
    var lowercase : Bool = false;
    var uppercase : Bool = false;
    let inputData : [Nat8] = input.encodeUtf8().toArray();

    for (i in Nat.range(0, inputData.size())) {
      let c : Nat8 = inputData[i];

      if (c == CHAR_1) {
        separatorIndex := i;
      } else if (isLowercase(c)) {
        lowercase := true;
      } else if (isUppercase(c)) {
        uppercase := true;
      };

      if (not isInRange(c)) {
        return #err("Found unexpected character: " # c.toText());
      };

    };

    if (lowercase and uppercase) {
      return #err("Inconsistent character casing in HRP.");
    };

    // Ensure length is within bounds.
    if (
      input.size() > 90 or separatorIndex == 0 or
      separatorIndex + 7 > input.size()
    ) {
      return #err("Bad separator position: " # (separatorIndex.toText()));
    };

    // Extract HRP
    let hrp = inputData.sliceToArray(0, separatorIndex).map(toLower);

    // Extract value data
    var error : ?Nat8 = null;
    let values = inputData.sliceToArray(separatorIndex + 1, inputData.size()).map(
      func(c) {
        let mappedVal : Nat8 = reverseCharset[c.toNat()];
        if (mappedVal == 255) error := ?c;
        mappedVal;
      }
    );

    // Return parsing error
    switch (error) {
      case (?c) return #err("Invalid character found: " # c.toText());
      case null {};
    };

    return switch (
      verifyChecksum(hrp, values),
      hrp.toBlob().decodeUtf8(),
    ) {
      case (#err(msg), _) {
        #err(msg);
      };
      case (#ok(encodingType), ?hrp) {
        // Strip the 6 checksum values from the end of the data.
        let output = values.sliceToArray(0, -6);
        #ok(encodingType, hrp, output);
      };
      case _ {
        #err("Failed to decode HRP.");
      };
    };
  };

  // Expand HRP for checksum computations by grouping together the first 3 bits
  // of all characters, then a zero, then the last 5 bits of all characters.
  // [a, b] => [a[:3], b[:3]] + [0] + [a[3:], b[3:]].
  func expandHrp(hrp : [Nat8]) : [Nat8] {
    let hrpSize = hrp.size();
    let outputSize = hrpSize * 2 + 1;
    let output = VarArray.repeat<Nat8>(0, outputSize);

    for (i in hrp.keys()) {
      let currHrp = hrp[i];
      output[i] := currHrp >> 5;
      output[i + hrpSize + 1] := currHrp & 0x1f;
    };

    output.toArray();
  };

  // Constant value associated to the given encoding.
  func encodingConstant(encoding : Encoding) : Nat32 {
    switch (encoding) {
      case (#BECH32) {
        1;
      };
      case (#BECH32M) {
        0x2bc830a3;
      };
    };
  };

  // Compute the checksum values for given hrp and data.
  func createChecksum(hrp : [Nat8], data : [Nat8], encoding : Encoding) : [Nat8] {
    let expandedHrp : [Nat8] = expandHrp(hrp);

    // Merge expandedHrp and data arrays and append 6 zeroes to get
    // [expandedHrp..., data..., 0, 0, 0, 0, 0, 0].
    let polyModValues : [Nat8] = [
      expandedHrp,
      data,
      [0, 0, 0, 0, 0, 0] : [Nat8],
    ].flatten();

    let mod : Nat32 = polymod(polyModValues) ^ encodingConstant(encoding);

    // Convert the 5-bit groups in mod to checksum data.
    Array.tabulate<Nat8>(
      6,
      func(i) {
        ((mod >> (5 * (5 - Nat32.fromIntWrap(i)))) & 31).toNat16().toNat8();
      },
    );
  };

  // Verify the checksum for the given bech32 data.
  func verifyChecksum(hrp : [Nat8], values : [Nat8]) : Result<Encoding, Text> {

    let expandedHrp : [Nat8] = expandHrp(hrp);

    let check : Nat32 = polymod(expandedHrp.concat(values));

    if (check == encodingConstant(#BECH32)) {
      #ok(#BECH32);
    } else if (check == encodingConstant(#BECH32M)) {
      #ok(#BECH32M);
    } else {
      #err("Checksum verification failed.");
    };
  };

  // Compute 6 5-bit values that make the checksum zero. Input values are
  // coefficients of a polynomial over GF(32) with an implicit 1 in front.
  // Returns the values packed inside a Nat32.
  func polymod(values : [Nat8]) : Nat32 {
    var c : Nat32 = 1;

    for (value in values.values()) {
      let c0 : Nat8 = (c >> 25).toNat16().toNat8();
      c := ((c & 0x1ffffff) << 5) ^ value.toNat16().toNat32();

      // Conditionally add in coefficients of the generator polynomial.
      if (c0 & 1 > 0) c ^= 0x3b6a57b2;
      if (c0 & 2 > 0) c ^= 0x26508e6d;
      if (c0 & 4 > 0) c ^= 0x1ea119fa;
      if (c0 & 8 > 0) c ^= 0x3d4233dd;
      if (c0 & 16 > 0) c ^= 0x2a1462b3;
    };
    c;
  };

  // If input corresponds to code of uppercase character, return code of its
  // lowercase version.
  func toLower(c : Nat8) : Nat8 {
    if (c >= CHAR_A and c <= CHAR_Z) {
      c + 0x20;
    } else {
      c;
    };
  };

  // Returns true if given code corresponds to a lowercase character.
  func isLowercase(c : Nat8) : Bool { (c >= CHAR_a and c <= CHAR_z) };

  // Returns true if given code corresponds to an uppercase character.
  func isUppercase(c : Nat8) : Bool { (c >= CHAR_A and c <= CHAR_Z) };

  // Check if given code is within range of human-readable characters.
  func isInRange(c : Nat8) : Bool {
    (c >= CHARS_LOWLIMIT and c <= CHARS_HIGHLIMIT);
  };
};
