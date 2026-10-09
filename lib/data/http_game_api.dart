import 'dart:async';
import 'dart:convert';

import 'package:coup_domain/coup_domain.dart';
import 'package:http/http.dart' as http;

import '../application/game_api.dart';

/// Talks to the game server (server/lib/src/http/api.dart).
class HttpGameApi implements GameApi {
  HttpGameApi({
    required this.baseUrl,
    required this.accessToken,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final Uri baseUrl;

  /// The current Supabase access token.
  final String? Function() accessToken;
  final http.Client _client;

  @override
  Future<bool> wakeUp() async {
    try {
      final response = await _client
          .get(baseUrl.resolve('health'))
          .timeout(const Duration(seconds: 90));
      return response.statusCode == 200;
    } on Exception {
      return false;
    }
  }

  @override
  Future<({String roomId, String code})> createRoom(String displayName) async {
    final json = await _post('rooms', {'displayName': displayName});
    return (roomId: json['roomId'] as String, code: json['code'] as String);
  }

  @override
  Future<String> joinRoom(String code, String displayName) async {
    final json = await _post('rooms/join', {
      'code': code,
      'displayName': displayName,
    });
    return json['roomId'] as String;
  }

  @override
  Future<void> startGame(String roomId) => _post('rooms/$roomId/start', {});

  @override
  Future<void> send(String roomId, GameCommand command) =>
      _post('rooms/$roomId/commands', command.toJson());

  Future<Map<String, Object?>> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    final http.Response response;
    try {
      response = await _client.post(
        baseUrl.resolve(path),
        headers: {
          'content-type': 'application/json',
          if (accessToken() case final token?) 'authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );
    } on Exception catch (e) {
      throw GameApiException(0, 'ติดต่อเซิร์ฟเวอร์ไม่ได้ ($e)');
    }

    final json = response.body.isEmpty ? null : _tryDecode(response.body);
    if (response.statusCode >= 400) {
      final message = json is Map && json['error'] is String
          ? json['error'] as String
          : 'Server error ${response.statusCode}';
      throw GameApiException(response.statusCode, message);
    }
    return json is Map<String, Object?> ? json : const {};
  }

  static Object? _tryDecode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }
}
