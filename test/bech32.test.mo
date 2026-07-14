import Char "mo:core/Char";
import Nat "mo:core/Nat";
import Runtime "mo:core/Runtime";
import Text "mo:core/Text";

import { test } "mo:test";

import Bech32 "../src/Bech32";

let validChecksumBech32 : [Text] = [
  "A12UEL5L",
  "a12uel5l",
  "an83characterlonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio1tt5tgs",
  "abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw",
  "11qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqc8247j",
  "split1checkupstagehandshakeupstreamerranterredcaperred2y9e3w",
  "?1ezyfcl",
  // HRP, separator, and data section all consist solely of numeric
  // characters (no alphabetic characters anywhere in the string). The
  // BECH32 standard does not require alphabetic characters; an all-digit
  // string is unambiguously single-case.
  "012854464896",
];

let validChecksumBech32m : [Text] = [
  "A1LQFN3A",
  "a1lqfn3a",
  "an83characterlonghumanreadablepartthatcontainsthetheexcludedcharactersbioandnumber11sg7hg6",
  "abcdef1l7aum6echk45nj3s0wdvt2fg8x9yrzpqzd3ryx",
  "11llllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllllludsr8",
  "split1checkupstagehandshakeupstreamerranterredcaperredlc445v",
  "?1v759aa",
  // HRP, separator, and data section all consist solely of numeric
  // characters (no alphabetic characters anywhere in the string). The
  // BECH32M standard does not require alphabetic characters; an all-digit
  // string is unambiguously single-case.
  "012343952083",
];

let invalidChecksumBech32 : [Text] = [
  // HRP character out of range.
  " 1nwldj5",
  // Overall max length exceeded.
  "an84characterslonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio1569pvx",
  // No separator character.
  "pzry9x0s0muk",
  // Empty HRP.
  "1pzry9x0s0muk",
  // Invalid data character.
  "x1b4n0q5v",
  // Too short checksum.
  "li1dgmt3",
  // Checksum calculated with uppercase form of HRP.
  "A1G7SGD8",
  // Empty HRP.
  "10a06t8",
  // Empty HRP.
  "1qzzfhee",
];

let invalidChecksumBech32m : [Text] = [
  // HRP character out of range.
  " 1xj0phk",
  // Overall max length exceeded.
  "an84characterslonghumanreadablepartthatcontainsthetheexcludedcharactersbioandnumber11d6pts4",
  // No separator character.
  "qyrz8wqd2c9m",
  // Empty HRP.
  "1qyrz8wqd2c9m",
  // Invalid data character.
  "y1b0jsk6g",
  // Invalid data character.
  "lt1igcx5c0",
  // Too short checksum.
  "in1muywd",
  // Invalid character in checksum.
  "mm1crxm3i",
  // Invalid character in checksum.
  "au1s5cgom",
  // Checksum calculated with uppercase form of HRP.
  "M1VUXWEZ",
  // Empty HRP.
  "16plkw9",
  // Empty HRP.
  "1p2gdwpf",
];

func toLower(text : Text) : Text {
  Text.map(
    text,
    func(c) {
      if (c >= 'A' and c <= 'Z') {
        return Char.fromNat32(Char.toNat32(c) + 0x20);
      };
      return c;
    },
  );
};

// Test checksum creation and validation.
func testValidChecksumBech32(testCase : Text) {
  switch (Bech32.decode(testCase)) {
    case (#ok((#BECH32, hrp, data))) {
      let encoded : Text = Bech32.encode(hrp, data, #BECH32);
      assert (toLower(testCase) == toLower(encoded));
    };
    case (#ok(_)) {
      Runtime.trap("Wrong encoding.");
    };
    case (#err(msg)) {
      Runtime.trap(msg);
    };
  };
};

// Test checksum creation and validation.
func testValidChecksumBech32m(testCase : Text) {
  switch (Bech32.decode(testCase)) {
    case (#ok((#BECH32M, hrp, data))) {
      let encoded : Text = Bech32.encode(hrp, data, #BECH32M);
      assert (toLower(testCase) == toLower(encoded));
    };
    case (#ok(_)) {
      Runtime.trap("Wrong encoding.");
    };
    case (#err(msg)) {
      Runtime.trap(msg);
    };
  };
};

// Test validation of invalid checksums.
func testInvalidChecksumBech32(testCase : Text) {
  switch (Bech32.decode(testCase)) {
    case (#ok(_)) {
      Runtime.trap("Parsed invalid string.");
    };
    case (#err(_)) {
      // Test passed.
    };
  };
};

// Test validation of invalid checksums.
func testInvalidChecksumBech32m(testCase : Text) {
  switch (Bech32.decode(testCase)) {
    case (#ok(_)) {
      Runtime.trap("Parsed invalid string.");
    };
    case (#err(_)) {
      // Test passed.
    };
  };
};

test(
  "valid bech32",
  func() {
    for (i in Nat.range(0, validChecksumBech32.size())) {
      testValidChecksumBech32(validChecksumBech32[i]);
    };
  },
);

test(
  "valid bech32m",
  func() {
    for (i in Nat.range(0, validChecksumBech32m.size())) {
      testValidChecksumBech32m(validChecksumBech32m[i]);
    };
  },
);

test(
  "invalid bech32",
  func() {
    for (i in Nat.range(0, invalidChecksumBech32.size())) {
      testInvalidChecksumBech32(invalidChecksumBech32[i]);
    };
  },
);

test(
  "invalid bech32m",
  func() {
    for (i in Nat.range(0, invalidChecksumBech32m.size())) {
      testInvalidChecksumBech32m(invalidChecksumBech32m[i]);
    };
  },
);
