/// ECDSA signature verification utilities.
///
/// ```motoko name=import
/// import Ecdsa "mo:bitcoin/ecdsa/Ecdsa";
/// ```

import Blob "mo:core/Blob";

import Sha256 "mo:sha2/Sha256";

import Common "../Common";
import Fp "../ec/Fp";
import Jacobi "../ec/Jacobi";
import Types "Types";

module {
  /// ECDSA signature type re-export.
  public type Signature = Types.Signature;
  /// ECDSA public key type re-export.
  public type PublicKey = Types.PublicKey;

  // Verify ECDSA signature using SHA256 as a hash function.
  /// Verifies an ECDSA signature for `message` using SHA-256 prehashing.
  ///
  /// Never traps. Returns `false` when:
  /// - `signature.r == 0` or `signature.s == 0`,
  /// - `signature.r >= curve.r` or `signature.s >= curve.r`,
  /// - the recovered point is at infinity, or its `x` coordinate (mod
  ///   `curve.r`) does not equal `signature.r`.
  ///
  /// Returns `true` only when the signature is valid for `message` under
  /// `publicKey`. The `publicKey` is assumed to have been validated by
  /// `Publickey.decode` (on-curve, not at infinity).
  public func verify(
    signature : Signature,
    publicKey : PublicKey,
    message : [Nat8],
  ) : Bool {

    let (x, y, curve) = (
      publicKey.coords.x,
      publicKey.coords.y,
      publicKey.curve,
    );

    if (
      signature.r == 0 or signature.s == 0 or
      signature.r >= curve.r or signature.s >= curve.r
    ) {
      return false;
    };

    let (r, s) : (Fp.Fp, Fp.Fp) = (Fp.Fp(signature.r, curve.r), Fp.Fp(signature.s, curve.r));
    let h : Fp.Fp = Fp.Fp(Common.readBE256(Sha256.fromArray(#sha256, message).toArray(), 0), curve.r);

    let sInverse : Fp.Fp = s.inverse();
    let a : Fp.Fp = h.mul(sInverse);
    let b : Fp.Fp = r.mul(sInverse);

    return switch (
      Jacobi.toAffine(
        Jacobi.add(
          Jacobi.mulBase(a.value, curve),
          Jacobi.mul(Jacobi.fromAffine(#point(x, y, curve)), b.value),
        )
      )
    ) {
      case (#point(x2, _, _)) {
        r.isEqual(Fp.Fp(x2.value, curve.r));
      };
      case _ {
        false;
      };
    };
  };
};
