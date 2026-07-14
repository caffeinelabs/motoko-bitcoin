/// Shared ECDSA type aliases and records.
///
/// ```motoko name=import
/// import Types "mo:bitcoin/ecdsa/Types";
/// ```

import Affine "../ec/Affine";
import Curves "../ec/Curves";
import Fp "../ec/Fp";

module {
  /// ECDSA private key scalar.
  ///
  /// A `Nat` interpreted as a 256-bit big-endian integer in
  /// `[1, n)` where `n` is the curve order.
  public type PrivateKey = Nat;
  /// ECDSA public key as an affine point on a curve.
  ///
  /// `coords` are the affine `(x, y)` coordinates as field elements.
  /// `curve` identifies the curve the point lies on.
  public type PublicKey = {
    coords : {
      x : Fp.Fp;
      y : Fp.Fp;
    };
    curve : Curves.Curve;
  };

  /// SEC1-encoded public key bytes paired with the curve.
  ///
  /// The byte array is either 33 bytes (compressed: leading `0x02`/`0x03`
  /// followed by the 32-byte x coordinate) or 65 bytes (uncompressed:
  /// leading `0x04` followed by 32-byte x and y coordinates).
  public type Sec1PublicKey = ([Nat8], Curves.Curve);
  /// Public key payload accepted by decoding APIs.
  public type EncodedPublicKey = {
    #sec1 : Sec1PublicKey;
    #point : Affine.Point;
  };

  /// ECDSA signature `(r, s)` scalars (raw, not DER-encoded).
  public type Signature = { r : Nat; s : Nat };
  /// ASN.1 DER encoded signature blob (the form used inside Bitcoin
  /// scriptSigs, before the trailing sighash type byte).
  public type DerSignature = Blob;
  /// Signature payload accepted by decoding APIs.
  public type EncodedSignature = {
    #der : DerSignature;
  };
};
