import 'dart:convert';
import 'dart:math';

import 'package:coup_domain/coup_domain.dart';
import 'package:coup_server/coup_server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// Accepts tokens of the form `token-<userId>`.
class FakeVerifier implements TokenVerifier {
  @override
  Future<String?> userIdFor(String token) async =>
      token.startsWith('token-') ? token.substring(6) : null;
}

void main() {
  late InMemoryRoomRepository repo;
  late Handler api;

  setUp(() {
    repo = InMemoryRoomRepository();
    api = buildApi(GameService(repo, random: Random(1)), FakeVerifier());
  });

  Future<Response> post(String path, {String? user, Object? body}) async => api(
    Request(
      'POST',
      Uri.parse('http://localhost$path'),
      headers: {'authorization': ?(user == null ? null : 'Bearer token-$user')},
      body: body is String ? body : jsonEncode(body ?? {}),
    ),
  );

  Future<Map<String, Object?>> json(Response response) async =>
      jsonDecode(await response.readAsString()) as Map<String, Object?>;

  Future<String> startedRoom() async {
    final created = await json(
      await post('/rooms', user: 'a', body: {'displayName': 'Ann'}),
    );
    await post(
      '/rooms/join',
      user: 'b',
      body: {'code': created['code'], 'displayName': 'Bo'},
    );
    final roomId = created['roomId'] as String;
    await post('/rooms/$roomId/start', user: 'a');
    return roomId;
  }

  test('health needs no token', () async {
    final response = await api(
      Request('GET', Uri.parse('http://localhost/health')),
    );
    expect(response.statusCode, 200);
  });

  test('everything else needs a valid token', () async {
    expect(
      (await post('/rooms', body: {'displayName': 'Ann'})).statusCode,
      401,
    );
    final response = await api(
      Request(
        'POST',
        Uri.parse('http://localhost/rooms'),
        headers: {'authorization': 'Bearer forged'},
        body: '{"displayName": "Ann"}',
      ),
    );
    expect(response.statusCode, 401);
  });

  test('create, join and start a room', () async {
    final created = await post(
      '/rooms',
      user: 'a',
      body: {'displayName': 'Ann'},
    );
    expect(created.statusCode, 201);
    final room = await json(created);

    final joined = await post(
      '/rooms/join',
      user: 'b',
      body: {'code': room['code'], 'displayName': 'Bo'},
    );
    expect(joined.statusCode, 200);
    expect((await json(joined))['roomId'], room['roomId']);

    final notHost = await post('/rooms/${room['roomId']}/start', user: 'b');
    expect(notHost.statusCode, 403);
    final started = await post('/rooms/${room['roomId']}/start', user: 'a');
    expect(started.statusCode, 204);
  });

  test('a command is applied as the signed-in user', () async {
    final roomId = await startedRoom();
    final response = await post(
      '/rooms/$roomId/commands',
      user: 'a',
      body: {'type': 'declareAction', 'action': 'income'},
    );
    expect(response.statusCode, 204);
    final game = CoupGame.fromJson(repo.lastUpdates[roomId]!.state);
    expect(game.player('a').coins, 2, reason: '2-player start: 1 + income');
  });

  test('illegal moves are 422 with the rule in the message', () async {
    final roomId = await startedRoom();
    final response = await post(
      '/rooms/$roomId/commands',
      user: 'b',
      body: {'type': 'declareAction', 'action': 'income'},
    );
    expect(response.statusCode, 422);
    expect((await json(response))['error'], contains('not b'));
  });

  test('malformed bodies are 400', () async {
    final roomId = await startedRoom();
    for (final body in [
      'not json',
      '[1, 2]',
      {'type': 'dance'},
      {'type': 'declareAction', 'action': 'fly'},
      {'type': 'block', 'character': 'king'},
      {'type': 'declareAction', 'action': 'coup', 'targetId': 7},
    ]) {
      final response = await post(
        '/rooms/$roomId/commands',
        user: 'a',
        body: body,
      );
      expect(response.statusCode, 400, reason: '$body');
    }
  });

  test('unknown rooms are 404', () async {
    final response = await post(
      '/rooms/nope/commands',
      user: 'a',
      body: {'type': 'pass'},
    );
    expect(response.statusCode, 404);
  });
}
