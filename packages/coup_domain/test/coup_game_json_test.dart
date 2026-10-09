import 'dart:convert';
import 'dart:math';

import 'package:coup_domain/coup_domain.dart';
import 'package:test/test.dart';

const duke = Character.duke;
const assassin = Character.assassin;
const captain = Character.captain;
const ambassador = Character.ambassador;
const contessa = Character.contessa;

CoupGame threePlayers() => CoupGame.fromPosition(
  players: [
    (id: 'a', hand: [assassin, ambassador], coins: 3),
    (id: 'b', hand: [contessa, duke], coins: 2),
    (id: 'c', hand: [captain, duke], coins: 2),
  ],
  deck: [captain, contessa, duke],
  random: Random(1),
);

/// Saves through a real JSON string, the way it will travel to the database.
CoupGame roundTrip(CoupGame game) => CoupGame.fromJson(
  jsonDecode(jsonEncode(game.toJson())) as Map<String, Object?>,
  random: Random(1),
);

void expectSameState(CoupGame game) {
  final restored = roundTrip(game);
  expect(restored.toJson(), game.toJson());
  expect(restored.phase.runtimeType, game.phase.runtimeType);
}

void main() {
  test('every phase survives a round trip', () {
    final game = threePlayers();
    expectSameState(game); // AwaitingAction

    game.declareAction('a', ActionType.assassinate, targetId: 'b');
    expectSameState(game); // AwaitingActionChallenge, empty passed
    game.pass('b');
    expectSameState(game); // AwaitingActionChallenge, passed: {b}
    game.pass('c');
    expectSameState(game); // AwaitingBlock
    game.block('b', contessa);
    expectSameState(game); // AwaitingBlockChallenge
    game.challenge('c');
    expectSameState(game); // AwaitingInfluenceLoss (c)
    game.loseInfluence('c', captain);
    expectSameState(game); // back to AwaitingAction, b's turn

    game.declareAction('b', ActionType.income);
    game.declareAction('c', ActionType.income);
    game.declareAction('a', ActionType.exchange);
    game.pass('b');
    game.pass('c');
    expect(game.phase, isA<AwaitingExchange>());
    expectSameState(game);
  });

  test('a restored game keeps playing from where it stopped', () {
    final game = threePlayers();
    game.declareAction('a', ActionType.assassinate, targetId: 'c');
    game.pass('b');
    game.challenge('c'); // wrong: a has the Assassin

    final restored = roundTrip(game);
    final loss = restored.phase as AwaitingInfluenceLoss;
    expect(loss.playerId, 'c');

    restored.loseInfluence('c', captain);
    restored.pass('c'); // c declines to block with the last card
    expect(restored.player('c').isAlive, isFalse);
    expect(restored.player('a').coins, 0);
    expect(restored.currentPlayer.id, 'b');
  });

  test('game over survives a round trip', () {
    final game = CoupGame.fromPosition(
      players: [
        (id: 'a', hand: [duke, duke], coins: 7),
        (id: 'b', hand: [captain], coins: 2),
      ],
      deck: [],
    );
    game.declareAction('a', ActionType.coup, targetId: 'b');
    final restored = roundTrip(game);
    expect((restored.phase as GameOver).winnerId, 'a');
  });

  test('a fresh random game survives a round trip', () {
    expectSameState(CoupGame.start(['a', 'b', 'c', 'd'], random: Random(7)));
  });

  group('rejects invalid saves', () {
    late Map<String, Object?> valid;
    setUp(() => valid = threePlayers().toJson());

    Map<String, Object?> withField(String key, Object? value) =>
        jsonDecode(jsonEncode({...valid, key: value})) as Map<String, Object?>;

    test('empty map', () {
      expect(() => CoupGame.fromJson({}), throwsFormatException);
    });

    test('unknown version', () {
      expect(
        () => CoupGame.fromJson(withField('version', 99)),
        throwsFormatException,
      );
    });

    test('unknown character in the deck', () {
      expect(
        () => CoupGame.fromJson(withField('deck', ['joker'])),
        throwsFormatException,
      );
    });

    test('current player out of range', () {
      expect(
        () => CoupGame.fromJson(withField('current', 3)),
        throwsFormatException,
      );
    });

    test('unknown phase', () {
      expect(
        () => CoupGame.fromJson(withField('phase', {'type': 'dancing'})),
        throwsFormatException,
      );
    });
  });
}
