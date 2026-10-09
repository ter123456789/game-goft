import 'dart:convert';

import 'package:coup_domain/coup_domain.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../application/app_exception.dart';
import '../application/game_service.dart';
import 'token_verifier.dart';

/// The HTTP API. Every route except `GET /health` needs
/// `Authorization: Bearer <Supabase access token>`.
///
/// - `POST /rooms` `{displayName}` → 201 `{roomId, code}`
/// - `POST /rooms/join` `{code, displayName}` → 200 `{roomId}`
/// - `POST /rooms/<roomId>/start` → 204
/// - `POST /rooms/<roomId>/commands` `{type, ...}` → 204, see [GameCommand.fromJson]
///
/// Clients read game state from Supabase (Realtime), not from this API.
Handler buildApi(GameService service, TokenVerifier verifier) {
  final router = Router()
    ..get('/health', (Request _) => Response.ok('ok'))
    ..post('/rooms', (Request request) async {
      final body = await _readJson(request);
      final room = await service.createRoom(
        _userId(request),
        _string(body, 'displayName'),
      );
      return _json(201, {'roomId': room.roomId, 'code': room.code});
    })
    ..post('/rooms/join', (Request request) async {
      final body = await _readJson(request);
      final roomId = await service.joinRoom(
        _userId(request),
        _string(body, 'code'),
        _string(body, 'displayName'),
      );
      return _json(200, {'roomId': roomId});
    })
    ..post('/rooms/<roomId>/start', (Request request, String roomId) async {
      await service.startGame(_userId(request), roomId);
      return Response(204);
    })
    ..post('/rooms/<roomId>/commands', (Request request, String roomId) async {
      final command = GameCommand.fromJson(await _readJson(request));
      await service.submit(_userId(request), roomId, command);
      return Response(204);
    });

  return const Pipeline()
      .addMiddleware(_handleErrors)
      .addMiddleware(_authenticate(verifier))
      .addHandler(router.call);
}

const _userIdKey = 'coup.userId';

Middleware _authenticate(TokenVerifier verifier) =>
    (inner) => (request) async {
      if (request.url.path == 'health') return inner(request);
      final header = request.headers['authorization'] ?? '';
      final token = header.startsWith('Bearer ') ? header.substring(7) : '';
      final userId = token.isEmpty ? null : await verifier.userIdFor(token);
      if (userId == null) return _error(401, 'Sign in first');
      return inner(request.change(context: {_userIdKey: userId}));
    };

Handler _handleErrors(Handler inner) => (request) async {
  try {
    return await inner(request);
  } on AppException catch (e) {
    final status = switch (e.kind) {
      AppErrorKind.notFound => 404,
      AppErrorKind.forbidden => 403,
      AppErrorKind.conflict => 409,
    };
    return _error(status, e.message);
  } on GameRuleException catch (e) {
    return _error(422, e.message);
  } on FormatException catch (e) {
    return _error(400, e.message);
  }
};

String _userId(Request request) => request.context[_userIdKey] as String;

Future<Map<String, Object?>> _readJson(Request request) async {
  final Object? body;
  try {
    body = jsonDecode(await request.readAsString());
  } on FormatException {
    throw const FormatException('Body must be JSON');
  }
  if (body is! Map<String, Object?>) {
    throw const FormatException('Body must be a JSON object');
  }
  return body;
}

String _string(Map<String, Object?> json, String key) => switch (json[key]) {
  final String value => value,
  _ => throw FormatException('$key must be a string'),
};

Response _json(int status, Map<String, Object?> body) => Response(
  status,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json'},
);

Response _error(int status, String message) =>
    _json(status, {'error': message});
