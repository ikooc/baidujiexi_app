/// Client request-signing used by the upstream convert API.
///
/// The upstream service issues a per-session `secret` and expects every
/// sensitive request to carry an `x-client-sign` header derived from it.
/// The algorithm is a concatenation of two classic non-cryptographic hashes
/// (FNV-1a 64-bit, then djb2 32-bit) over `"<secret>|<payload>"`, hex-encoded.
///
/// Both hashes operate on UTF-16 code units, matching JavaScript's
/// `String.prototype.charCodeAt`, so Dart's `String.codeUnitAt` is used
/// directly. `BigInt` is used for the 64-bit FNV step to keep the result
/// identical regardless of the host integer width.
library;

final BigInt _mask64 = (BigInt.one << 64) - BigInt.one;
final BigInt _mask32 = (BigInt.one << 32) - BigInt.one;
final BigInt _fnvOffsetBasis = BigInt.parse('cbf29ce484222325', radix: 16);
final BigInt _fnvPrime = BigInt.parse('100000001b3', radix: 16);
final BigInt _thirtyThree = BigInt.from(33);

/// Computes the upstream `x-client-sign` value for the given [payload].
String clientSign(String secret, String payload) {
  final input = '$secret|$payload';

  var fnv = _fnvOffsetBasis;
  for (var i = 0; i < input.length; i++) {
    fnv = (fnv ^ BigInt.from(input.codeUnitAt(i))) & _mask64;
    fnv = (fnv * _fnvPrime) & _mask64;
  }

  var djb2 = BigInt.from(5381);
  for (var i = 0; i < input.length; i++) {
    djb2 = ((djb2 * _thirtyThree) ^ BigInt.from(input.codeUnitAt(i))) & _mask32;
  }

  return fnv.toRadixString(16).padLeft(16, '0') +
      djb2.toRadixString(16).padLeft(8, '0');
}
