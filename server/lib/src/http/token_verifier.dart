/// Turns a bearer token into the id of the signed-in user.
abstract interface class TokenVerifier {
  /// Returns null if the token is invalid or expired.
  Future<String?> userIdFor(String token);
}
