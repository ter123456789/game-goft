import 'dart:convert';
import 'dart:math';

import 'package:coup_domain/coup_domain.dart';
import 'package:test/test.dart';

const duke = Character.duke;
const assassin = Character.assassin;
const captain = Character.captain;
const ambassador = Character.ambassador;
const contessa = Character.contessa;

const ids = ['a', 'b', 'c', 'd'];

/// Players are named a, b, c… in order; a moves first. An empty hand is a
/// player who is already out.
CoupGame setup(
  List<List<Character>> hands, {
  List<int>? coins,
  List<Character> deck = const [captain, contessa, duke],
}) => CoupGame.fromPosition(
  players: [
    for (final (i, hand) in hands.indexed)
      (id: ids[i], hand: hand, coins: coins?[i] ?? 2),
  ],
  deck: deck,
  random: Random(1),
);

Matcher throwsRule = throwsA(isA<GameRuleException>());

void main() {
  group('waitingFor', () {
    test('follows the turn through every response window', () {
      final game = setup(
        [
          [assassin, duke],
          [contessa, duke],
          [captain, duke],
        ],
        coins: [3, 2, 2],
      );
      expect(game.waitingFor, {'a'});

      game.declareAction('a', ActionType.assassinate, targetId: 'b');
      expect(game.waitingFor, {'b', 'c'});
      game.pass('b');
      expect(game.waitingFor, {'c'});
      game.pass('c');
      expect(game.waitingFor, {'b'}, reason: 'only the target may block');

      game.block('b', contessa);
      expect(game.waitingFor, {'a', 'c'});
      game.challenge('c');
      expect(game.waitingFor, {'c'}, reason: 'c must pick a card to lose');
    });

    test('is empty once the game is over', () {
      final game = setup(
        [
          [duke],
          [captain],
        ],
        coins: [7, 2],
      );
      game.declareAction('a', ActionType.coup, targetId: 'b');
      expect(game.waitingFor, isEmpty);
    });
  });

  group('timeOut', () {
    test('an idle player takes income', () {
      final game = setup([
        [duke, duke],
        [captain, captain],
      ]);
      game.timeOut();
      expect(game.player('a').coins, 3);
      expect(game.currentPlayer.id, 'b');
    });

    test('an idle player with 10 coins coups the next living player', () {
      final game = setup(
        [
          [duke, duke],
          [],
          [captain, contessa],
        ],
        coins: [10, 0, 2],
      );
      game.timeOut();
      expect(game.player('a').coins, 3);
      final loss = game.phase as AwaitingInfluenceLoss;
      expect(loss.playerId, 'c');
    });

    test('players who have not answered a claim pass', () {
      final game = setup([
        [captain, captain],
        [duke, duke],
        [duke, duke],
      ]);
      game.declareAction('a', ActionType.tax);
      game.pass('b');
      game.timeOut();
      expect(game.player('a').coins, 5);
      expect(game.currentPlayer.id, 'b');
    });

    test('an idle target does not block', () {
      final game = setup([
        [captain, duke],
        [duke, duke],
      ]);
      game.declareAction('a', ActionType.steal, targetId: 'b');
      game.pass('b');
      game.timeOut();
      expect(game.player('a').coins, 4);
    });

    test('nobody challenging a block lets the block stand', () {
      final game = setup([
        [duke, duke],
        [captain, captain],
        [captain, captain],
      ]);
      game.declareAction('a', ActionType.foreignAid);
      game.block('b', duke);
      game.timeOut();
      expect(game.player('a').coins, 2);
      expect(game.currentPlayer.id, 'b');
    });

    test('an idle player losing influence reveals their first card', () {
      final game = setup(
        [
          [duke, duke],
          [captain, contessa],
        ],
        coins: [7, 2],
      );
      game.declareAction('a', ActionType.coup, targetId: 'b');
      game.timeOut();
      expect(game.player('b').hiddenCharacters, [contessa]);
    });

    test('an idle exchanger keeps their original hand', () {
      final game = setup([
        [ambassador, duke],
        [captain, captain],
      ]);
      game.declareAction('a', ActionType.exchange);
      game.pass('b');
      game.timeOut();
      expect(game.player('a').hiddenCharacters, [ambassador, duke]);
      expect(game.deckSize, 3);
    });

    test('cannot be used once the game is over', () {
      final game = setup(
        [
          [duke],
          [captain],
        ],
        coins: [7, 2],
      );
      game.declareAction('a', ActionType.coup, targetId: 'b');
      expect(game.timeOut, throwsRule);
    });
  });

  group('revision', () {
    test('goes up with every move and not on illegal ones', () {
      final game = setup([
        [duke, duke],
        [captain, captain],
        [captain, captain],
      ]);
      expect(game.revision, 0);

      game.declareAction('a', ActionType.tax);
      final afterClaim = game.revision;
      expect(afterClaim, greaterThan(0));

      expect(() => game.pass('a'), throwsRule);
      expect(game.revision, afterClaim);

      game.pass('b');
      expect(game.revision, greaterThan(afterClaim));
    });

    test('is kept when saving and restoring', () {
      final game = setup([
        [duke, duke],
        [captain, captain],
      ]);
      game.declareAction('a', ActionType.income);
      final restored = CoupGame.fromJson(
        jsonDecode(jsonEncode(game.toJson())) as Map<String, Object?>,
      );
      expect(restored.revision, game.revision);
    });
  });

  group('publicView', () {
    test('shows coins, revealed cards and how many cards are hidden', () {
      final game = setup(
        [
          [duke, duke],
          [captain, contessa],
        ],
        coins: [7, 2],
      );
      game.declareAction('a', ActionType.coup, targetId: 'b');
      game.loseInfluence('b', contessa);

      final view = game.publicView();
      final b = view.players.firstWhere((p) => p.id == 'b');
      expect(b.revealed, [contessa]);
      expect(b.hiddenCount, 1);
      expect(view.players.first.coins, 0);
      expect(view.currentPlayerId, 'b');
      expect(view.waitingFor, {'b'});
      expect(view.revision, game.revision);
    });

    test('never contains a hidden card, even during an exchange', () {
      final game = setup(
        [
          [ambassador, duke],
          [captain, assassin],
        ],
        deck: [contessa, captain, duke],
      );
      game.declareAction('a', ActionType.exchange);
      game.pass('b');
      expect(game.phase, isA<AwaitingExchange>());

      final json = jsonEncode(game.publicView().toJson());
      for (final c in Character.values) {
        expect(json, isNot(contains(c.name)));
      }
      expect((game.publicView().phase as AwaitingExchange).keepCount, 2);
    });

    test('survives a JSON round trip', () {
      final game = setup(
        [
          [assassin, duke],
          [contessa, duke],
          [captain, duke],
        ],
        coins: [3, 2, 2],
      );
      game.declareAction('a', ActionType.assassinate, targetId: 'b');
      game.pass('b');
      game.pass('c');
      game.block('b', contessa);

      final view = game.publicView();
      final restored = PublicGameView.fromJson(
        jsonDecode(jsonEncode(view.toJson())) as Map<String, Object?>,
      );
      expect(restored.toJson(), view.toJson());
      expect(restored.phase, isA<AwaitingBlockChallenge>());
    });
  });

  group('privateView', () {
    test('shows only your own hand', () {
      final game = setup([
        [ambassador, duke],
        [captain, assassin],
      ]);
      expect(game.privateView('a').hand, [ambassador, duke]);
      expect(game.privateView('b').hand, [captain, assassin]);
      expect(game.privateView('a').exchangeOptions, isNull);
    });

    test('gives exchange options to the exchanger only', () {
      final game = setup(
        [
          [ambassador, duke],
          [captain, assassin],
        ],
        deck: [contessa, captain, duke],
      );
      game.declareAction('a', ActionType.exchange);
      game.pass('b');
      expect(game.privateView('a').exchangeOptions, [
        ambassador,
        duke,
        contessa,
        captain,
      ]);
      expect(game.privateView('b').exchangeOptions, isNull);
    });

    test('survives a JSON round trip', () {
      final game = setup([
        [ambassador, duke],
        [captain, assassin],
      ]);
      game.declareAction('a', ActionType.exchange);
      game.pass('b');
      for (final id in ['a', 'b']) {
        final view = game.privateView(id);
        final restored = PrivateView.fromJson(
          jsonDecode(jsonEncode(view.toJson())) as Map<String, Object?>,
        );
        expect(restored.toJson(), view.toJson());
      }
    });

    test('rejects an unknown player', () {
      final game = setup([
        [duke, duke],
        [captain, captain],
      ]);
      expect(() => game.privateView('z'), throwsRule);
    });
  });
}
