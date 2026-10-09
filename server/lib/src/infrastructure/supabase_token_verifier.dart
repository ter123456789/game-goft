import 'package:supabase/supabase.dart';

import '../http/token_verifier.dart';

/// Checks a user's Supabase access token with the Supabase Auth server.
class SupabaseTokenVerifier implements TokenVerifier {
  SupabaseTokenVerifier(this._client);

  final SupabaseClient _client;

  @override
  Future<String?> userIdFor(String token) async {
    try {
      return (await _client.auth.getUser(token)).user?.id;
    } on AuthException {
      return null;
    }
  }
}
