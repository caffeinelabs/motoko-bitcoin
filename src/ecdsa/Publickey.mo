/// Public key decoding and SEC1 conversion utilities.
///
/// ```motoko name=import
/// import Publickey "mo:bitcoin/ecdsa/Publickey";
/// ```

import { type Result } "mo:core/Types";

import Affine "../ec/Affine";
import Curves "../ec/Curves";
import Types "Types";

module {
  type PublicKey = Types.PublicKey;
  type EncodedPublicKey = Types.EncodedPublicKey;

  /// Decodes a public key from encoded point or SEC1 bytes.
  ///
  /// Never traps. Returns `#err(message)` when:
  /// - the input is `#sec1` and `Affine.fromBytes` fails (size mismatch,
  ///   bad leading byte, or off-curve point) —
  ///   `"Could not deserialize data."`,
  /// - the decoded point is at infinity —
  ///   `"Can't create public key from point at infinity."`,
  /// - the input is `#point` and the point is not on its curve —
  ///   `"Point not on curve."`.
  public func decode(pk : EncodedPublicKey) : Result<Types.PublicKey, Text> {
    switch (pk) {
      case (#point(point)) {
        fromPoint(point);
      };
      case (#sec1(data, curve)) {
        fromBytes(data, curve);
      };
    };
  };

  // Deserialize given data to public key. This supports compressed and
  // uncompressed SEC-1 formats.
  // Returns error result if deserialize fails or deserialized point is at
  // infinity.
  func fromBytes(data : [Nat8], curve : Curves.Curve) : Result<PublicKey, Text> {

    switch (Affine.fromBytes(data, curve)) {
      case (null) {
        #err("Could not deserialize data.");
      };
      case (?(point)) {
        fromPoint(point);
      };
    };
  };

  // Creates a PublicKey out of given point.
  // Returns error if point is at infinity or not on curve.
  func fromPoint(point : Affine.Point) : Result<PublicKey, Text> {
    switch (point) {
      case (#infinity(_)) {
        #err("Can't create public key from point at infinity.");
      };
      case (#point p) {
        if (Affine.isOnCurve(point)) {
          #ok({
            coords = {
              x = p.0;
              y = p.1;
            };
            curve = p.2;
          });
          // #ok(_PublicKey(p))
        } else {
          #err("Point not on curve.");
        };
      };
    };
  };

  /// Encodes a public key to compressed or uncompressed SEC1 form.
  ///
  /// `compressed = true` returns 33 bytes (`0x02`/`0x03` prefix + 32-byte x).
  /// `compressed = false` returns 65 bytes (`0x04` prefix + 32-byte x + 32-byte y).
  ///
  /// Never traps. The returned tuple pairs the SEC1 byte encoding with the
  /// curve the key belongs to.
  public func toSec1(
    pk : PublicKey,
    compressed : Bool,
  ) : Types.Sec1PublicKey {
    let point : Affine.Point = #point(pk.coords.x, pk.coords.y, pk.curve);
    (Affine.toBytes(point, compressed), pk.curve);
  };
};
