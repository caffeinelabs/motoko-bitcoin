import TestUtils "../TestUtils";
import Wif "../../src/bitcoin/Wif";

type ValidWifTestCase = {
  wif : Text;
  compressed : Bool;
  privateKey : Nat;
  version : Nat8;
};

type InvalidWifTestCase = {
  wif : Text;
};

let validWifTestCases : [ValidWifTestCase] = [
  {
    wif = "KwDiBf89QgGbjEhKnhXJuH7LrciVrZi3qYjgd9M7rFU73sVHnoWn";
    compressed = true;
    privateKey = 1;
    version = 0x80;
  },
  {
    wif = "5HpHagT65TZzG1PH3CSu63k8DbpvD8s5ip4nEB3kEsreAnchuDf";
    compressed = false;
    privateKey = 1;
    version = 0x80;
  },
  {
    wif = "KxhEDBQyyEFymvfJD96q8stMbJMbZUb6D1PmXqBWZDU2WvbvVs9o";
    compressed = true;
    privateKey = 19898843618908353587043383062236220484949425084007183071220218307100305431102;
    version = 0x80;
  },
  {
    wif = "KzrA86mCVMGWnLGBQu9yzQa32qbxb5dvSK4XhyjjGAWSBKYX4rHx";
    compressed = true;
    privateKey = 48968302285117906840285529799176770990048954789747953886390402978935544927851;
    version = 0x80;
  },
  {
    wif = "5JdxzLtFPHNe7CAL8EBC6krdFv9pwPoRo4e3syMZEQT9srmK8hh";
    compressed = false;
    privateKey = 48968302285117906840285529799176770990048954789747953886390402978935544927851;
    version = 0x80;
  },
  {
    wif = "cRD9b1m3vQxmwmjSoJy7Mj56f4uNFXjcWMCzpQCEmHASS4edEwXv";
    compressed = true;
    privateKey = 48968302285117906840285529799176770990048954789747953886390402978935544927851;
    version = 0xef;
  },
  {
    wif = "92Qba5hnyWSn5Ffcka56yMQauaWY6ZLd91Vzxbi4a9CCetaHtYj";
    compressed = false;
    privateKey = 48968302285117906840285529799176770990048954789747953886390402978935544927851;
    version = 0xef;
  },
  {
    wif = "L5oLkpV3aqBjhki6LmvChTCV6odsp4SXM6FfU2Gppt5kFLaHLuZ9";
    compressed = true;
    privateKey = 115792089237316195423570985008687907852837564279074904382605163141518161494336;
    version = 0x80;
  },
  {
    wif = "5K1DDRAqBPyuhQCRTpkxqofENVqUS2R3kwTAMncf46HkZ9BXaRq";
    compressed = false;
    privateKey = 70787862713293963375496916313032781152406131251747803633065018970699502141044;
    version = 0x80;
  },
];

let invalidWifTestCases : [InvalidWifTestCase] = [
  {
    // Bad checksum.
    wif = "92Qba5hnyWSn5Ffcka56yMQauaWY6ZLd91Vzxbi4a9CCetaHtYJ";
  },
  {
    // Bad network version.
    wif = "ZHqTSuFjkEYbX7RvuF41tWVois3dA2ydMX731aFihYKHWYtDNA";
  },
  {
    // Invalid compression flag.
    wif = "KwDiBf89QgGbjEhKnhXJuH7LrciVrZi3qYjgd9M7rFU73sfZr2ym";
  },
  {
    // Invalid length.
    wif = "3tq8Vmhh9SN5XhjTGSWgx8iKk59XbKG6UH4oqpejRuJhfYD";
  },
  {
    // Invalid length.
    wif = "38uMpGARR2BJy5p4dNFKYg9UsWNoBtkpbdrXDjmfvz8krCtw3T1W92ZDSR";
  },
];

// Vectors that exercise the secp256k1 private-scalar guard
// (`privateKey == 0` or `privateKey >= Curves.secp256k1.r`). All of
// these decode to a syntactically valid WIF whose 32-byte payload is
// either zero or `>= r`, so `Wif.decode` must reject them with the exact
// error message "Invalid private scalar."
type InvalidScalarWifTestCase = {
  wif : Text;
};

let invalidScalarWifTestCases : [InvalidScalarWifTestCase] = [
  {
    // Zero scalar (mainnet, compressed).
    wif = "KwDiBf89QgGbjEhKnhXJuH7LrciVrZi3qYjgd9M7rFU73Nd2Mcv1";
  },
  {
    // Zero scalar (mainnet, uncompressed).
    wif = "5HpHagT65TZzG1PH3CSu63k8DbpvD8s5ip4nEB3kEsreAbuatmU";
  },
  {
    // Zero scalar (testnet, compressed).
    wif = "cMahea7zqjxrtgAbB7LSGbcQUr1uX1ojuat9jZodMN87J7g8rY9t";
  },
  {
    // Scalar equal to secp256k1 group order r (mainnet, compressed).
    wif = "L5oLkpV3aqBjhki6LmvChTCV6odsp4SXM6FfU2Gppt5kFqRzExJJ";
  },
  {
    // Scalar equal to r + 1 (mainnet, uncompressed).
    wif = "5Km2kuu7vtFDPpxywn4u3NLpbr5jKpTB3jsuDU2KYEqetyuszSh";
  },
];

func testValidWifDecode(tcase : ValidWifTestCase) {
  switch (Wif.decode(tcase.wif)) {
    case (#ok(privateKey)) {
      assert (privateKey.key == tcase.privateKey);
      assert (privateKey.compressedPublicKey == tcase.compressed);
    };
    case _ {
      assert (false);
    };
  };
};

func testInvalidWifDecode(tcase : InvalidWifTestCase) {
  switch (Wif.decode(tcase.wif)) {
    case (#ok(_privateKey)) {
      assert (false);
    };
    case _ {
      // Ok.
    };
  };
};

func testInvalidScalarWifDecode(tcase : InvalidScalarWifTestCase) {
  switch (Wif.decode(tcase.wif)) {
    case (#err(msg)) {
      assert (msg == "Invalid private scalar.");
    };
    case (#ok(_privateKey)) {
      assert (false);
    };
  };
};

let runTest = TestUtils.runTestWithDefaults;

runTest({
  title = "Decode valid Wifs";
  fn = testValidWifDecode;
  vectors = validWifTestCases;
});

runTest({
  title = "Decode invalid Wifs";
  fn = testInvalidWifDecode;
  vectors = invalidWifTestCases;
});

runTest({
  title = "Decode WIFs with out-of-range private scalar";
  fn = testInvalidScalarWifDecode;
  vectors = invalidScalarWifTestCases;
});
