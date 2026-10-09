import 'dart:math';

import 'package:coup_domain/coup_domain.dart';
import 'package:coup_server/coup_server.dart';
import 'package:test/test.dart';

/// Fails the first [failures] saves, as if another server saved first.
class RacingRepository extends InMemoryRoomRepository {
  RacingRepository(this.failures);

  int failures;

  @override
  Future<bool> saveGame(GameUpdate update) async {
    if (update.expectedRevision != null && failures > 0) {
      failures--;
      return false;
    }
    return super.saveGame(update);
  }
}

Matcher throwsApp(AppErrorKind kind) =>
    throwsA(isA<AppException>().having((e) => e.kind, 'kind', kind));

final throwsRule = throwsA(isA<GameRuleException>());

void main() {
  late InMemoryRoomRepository repo;
  late DateTime now;
  late GameService service;

  GameService makeService(InMemoryRoomRepository repository) => GameService(
    repository,
    turnTimeout: const Duration(seconds: 30),
    now: () => now,
    random: Random(1),
  );

  setUp(() {
    repo = InMemoryRoomRepository();
    now = DateTime.utc(2026, 10, 9, 12);
    service = makeService(repo);
  });

  /// A started game with players a (host), b and c.
  Future<String> startedRoom() async {
    final room = await service.createRoom('a', 'Ann');
    await service.joinRoom('b', room.code, 'Bo');
    await service.joinRoom('c', room.code, 'Cy');
    await service.startGame('a', room.roomId);
    return room.roomId;
  }

  CoupGame loadGame(String roomId) =>
      CoupGame.fromJson(repo.lastUpdates[roomId]!.state);

  group('rooms', () {
    test('the creator is the host in seat 0, with a 6-letter code', () async {
      final room = await service.createRoom('a', '  Ann  ');
      expect(room.code, matches(RegExp(r'^[A-HJ-NP-Z2-9]{6}$')));
      final players = await repo.players(room.roomId);
      expect(players.single.userId, 'a');
      expect(players.single.displayName, 'Ann');
      expect((await repo.findRoom(room.roomId))!.hostId, 'a');
    });

    test(
      'players join by code in any case, and joining twice is fine',
      () async {
        final room = await service.createRoom('a', 'Ann');
        await service.joinRoom('b', room.code.toLowerCase(), 'Bo');
        await service.joinRoom('b', room.code, 'Bo');
        final seats = [for (final p in await repo.players(room.roomId)) p.seat];
        expect(seats, [0, 1]);
      },
    );

    test('rejects unknown codes, full rooms and blank names', () async {
      await expectLater(
        service.joinRoom('b', 'ZZZZZZ', 'Bo'),
        throwsApp(AppErrorKind.notFound),
      );

      final room = await service.createRoom('a', 'Ann');
      for (final id in ['b', 'c', 'd', 'e', 'f']) {
        await service.joinRoom(id, room.code, id);
      }
      await expectLater(
        service.joinRoom('g', room.code, 'g'),
        throwsApp(AppErrorKind.conflict),
      );
      await expectLater(service.createRoom('a', '   '), throwsFormatException);
    });

    test('nobody can join once the game has started', () async {
      final roomId = await startedRoom();
      final code = (await repo.findRoom(roomId))!.code;
      await expectLater(
        service.joinRoom('d', code, 'Di'),
        throwsApp(AppErrorKind.conflict),
      );
    });
  });

  group('startGame', () {
    test('deals a game and writes every view', () async {
      final roomId = await startedRoom();
      final update = repo.lastUpdates[roomId]!;
      expect((await repo.findRoom(roomId))!.status, RoomStatus.playing);
      expect(update.deadlineAt, now.add(const Duration(seconds: 30)));
      expect(update.hands.keys, unorderedEquals(['a', 'b', 'c']));

      final view = PublicGameView.fromJson(update.publicView);
      expect(view.currentPlayerId, 'a', reason: 'seat order is turn order');
      expect([for (final p in view.players) p.id], ['a', 'b', 'c']);
    });

    test('each hand row holds only that player\'s cards', () async {
      final roomId = await startedRoom();
      final update = repo.lastUpdates[roomId]!;
      final game = loadGame(roomId);
      for (final id in ['a', 'b', 'c']) {
        final hand = PrivateView.fromJson(update.hands[id]!);
        expect(hand.playerId, id);
        expect(hand.hand, game.player(id).hiddenCharacters);
      }
    });

    test('only the host can start, only once, and with 2+ players', () async {
      final room = await service.createRoom('a', 'Ann');
      await expectLater(service.startGame('a', room.roomId), throwsRule);
      await service.joinRoom('b', room.code, 'Bo');
      await expectLater(
        service.startGame('b', room.roomId),
        throwsApp(AppErrorKind.forbidden),
      );
      await service.startGame('a', room.roomId);
      await expectLater(
        service.startGame('a', room.roomId),
        throwsApp(AppErrorKind.conflict),
      );
      await expectLater(
        service.startGame('a', 'nope'),
        throwsApp(AppErrorKind.notFound),
      );
    });
  });

  group('submit', () {
    test('applies a move and saves the new revision and deadline', () async {
      final roomId = await startedRoom();
      now = now.add(const Duration(seconds: 10));
      await service.submit(
        'a',
        roomId,
        const DeclareActionCommand(ActionType.income),
      );
      final update = repo.lastUpdates[roomId]!;
      expect(loadGame(roomId).player('a').coins, 3);
      expect(update.expectedRevision, 0);
      expect(update.revision, greaterThan(0));
      expect(update.deadlineAt, now.add(const Duration(seconds: 30)));
    });

    test('rejects illegal moves without saving anything', () async {
      final roomId = await startedRoom();
      final before = repo.lastUpdates[roomId];
      await expectLater(
        service.submit(
          'b',
          roomId,
          const DeclareActionCommand(ActionType.income),
        ),
        throwsRule,
      );
      await pumpEventQueue();
      expect(repo.lastUpdates[roomId], same(before));
    });

    test('rejects players who are not in the game', () async {
      final roomId = await startedRoom();
      await expectLater(
        service.submit('z', roomId, const PassCommand()),
        throwsApp(AppErrorKind.forbidden),
      );
      await expectLater(
        service.submit('a', 'nope', const PassCommand()),
        throwsApp(AppErrorKind.notFound),
      );
    });

    test('retries when another save wins the race', () async {
      repo = RacingRepository(2);
      service = makeService(repo);
      final roomId = await startedRoom();
      await service.submit(
        'a',
        roomId,
        const DeclareActionCommand(ActionType.income),
      );
      expect(loadGame(roomId).player('a').coins, 3);
    });

    test('gives up after repeated races', () async {
      repo = RacingRepository(3);
      service = makeService(repo);
      final roomId = await startedRoom();
      await expectLater(
        service.submit(
          'a',
          roomId,
          const DeclareActionCommand(ActionType.income),
        ),
        throwsApp(AppErrorKind.conflict),
      );
    });
  });

  group('expireOverdue', () {
    test('does nothing before the deadline', () async {
      final roomId = await startedRoom();
      now = now.add(const Duration(seconds: 29));
      expect(await service.expireOverdue(), 0);
      expect(loadGame(roomId).player('a').coins, 2);
    });

    test('moves for the idle player once time is up', () async {
      final roomId = await startedRoom();
      now = now.add(const Duration(seconds: 31));
      expect(await service.expireOverdue(), 1);
      final game = loadGame(roomId);
      expect(game.player('a').coins, 3, reason: 'idle player takes income');
      expect(game.currentPlayer.id, 'b');
      expect(
        repo.lastUpdates[roomId]!.deadlineAt,
        now.add(const Duration(seconds: 30)),
      );
    });

    test('marks the room finished when the game ends', () async {
      final room = await service.createRoom('a', 'Ann');
      await service.joinRoom('b', room.code, 'Bo');
      await service.startGame('a', room.roomId);

      // Let the clock run until someone wins on timeouts alone.
      for (var i = 0; i < 200; i++) {
        now = now.add(const Duration(seconds: 31));
        if (await service.expireOverdue() == 0) break;
      }
      final update = repo.lastUpdates[room.roomId]!;
      expect(loadGame(room.roomId).phase, isA<GameOver>());
      expect(update.deadlineAt, isNull);
      expect((await repo.findRoom(room.roomId))!.status, RoomStatus.finished);
    });
  });
}
