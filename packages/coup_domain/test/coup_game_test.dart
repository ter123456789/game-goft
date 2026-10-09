import 'dart:math';

import 'package:test/test.dart';
import 'package:coup_domain/coup_domain.dart';

const duke = Character.duke;
const assassin = Character.assassin;
const captain = Character.captain;
const ambassador = Character.ambassador;
const contessa = Character.contessa;

const ids = ['a', 'b', 'c', 'd', 'e', 'f'];

/// Players are named a, b, c… in order; a moves first.
CoupGame setup(
  List<List<Character>> hands, {
  List<int>? coins,
  List<Character> deck = const [captain, contessa, duke, assassin, ambassador],
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
  group('start', () {
    test('deals 2 cards and 2 coins to each player', () {
      final game = CoupGame.start(['a', 'b', 'c'], random: Random(1));
      for (final p in game.players) {
        expect(p.hiddenCharacters, hasLength(2));
        expect(p.coins, 2);
      }
      expect(game.deckSize, 15 - 6);
      expect(game.phase, isA<AwaitingAction>());
    });

    test('two-player game: the starting player gets 1 coin', () {
      final game = CoupGame.start(['a', 'b'], random: Random(1));
      expect(game.player('a').coins, 1);
      expect(game.player('b').coins, 2);
    });

    test('rejects fewer than 2 or more than 6 players, and duplicate ids', () {
      expect(() => CoupGame.start(['a']), throwsRule);
      expect(() => CoupGame.start(ids + ['g']), throwsRule);
      expect(() => CoupGame.start(['a', 'a']), throwsRule);
    });
  });

  group('general actions', () {
    test('income gives 1 coin and passes the turn', () {
      final game = setup([
        [duke, duke],
        [captain, captain],
      ]);
      game.declareAction('a', ActionType.income);
      expect(game.player('a').coins, 3);
      expect(game.currentPlayer.id, 'b');
    });

    test('only the current player may act', () {
      final game = setup([
        [duke, duke],
        [captain, captain],
      ]);
      expect(() => game.declareAction('b', ActionType.income), throwsRule);
    });

    test('with 10 coins a player must coup', () {
      final game = setup(
        [
          [duke, duke],
          [captain, captain],
        ],
        coins: [10, 2],
      );
      expect(() => game.declareAction('a', ActionType.income), throwsRule);
      game.declareAction('a', ActionType.coup, targetId: 'b');
      expect(game.player('a').coins, 3);
    });

    test('coup needs 7 coins and a living target other than yourself', () {
      final game = setup(
        [
          [duke, duke],
          [captain, captain],
        ],
        coins: [6, 2],
      );
      expect(
        () => game.declareAction('a', ActionType.coup, targetId: 'b'),
        throwsRule,
      );
      final rich = setup(
        [
          [duke, duke],
          [captain, captain],
        ],
        coins: [7, 2],
      );
      expect(() => rich.declareAction('a', ActionType.coup), throwsRule);
      expect(
        () => rich.declareAction('a', ActionType.coup, targetId: 'a'),
        throwsRule,
      );
    });

    test('coup makes the target choose a card to lose', () {
      final game = setup(
        [
          [duke, duke],
          [captain, contessa],
          [duke, duke],
        ],
        coins: [7, 2, 2],
      );
      game.declareAction('a', ActionType.coup, targetId: 'b');

      final phase = game.phase as AwaitingInfluenceLoss;
      expect(phase.playerId, 'b');
      expect(() => game.loseInfluence('b', duke), throwsRule);

      game.loseInfluence('b', contessa);
      expect(game.player('b').hiddenCharacters, [captain]);
      expect(game.currentPlayer.id, 'b');
    });
  });

  group('foreign aid', () {
    test('gives 2 coins when nobody blocks', () {
      final game = setup([
        [duke, duke],
        [captain, captain],
        [captain, captain],
      ]);
      game.declareAction('a', ActionType.foreignAid);
      expect(game.phase, isA<AwaitingBlock>());
      game.pass('b');
      game.pass('c');
      expect(game.player('a').coins, 4);
      expect(game.currentPlayer.id, 'b');
    });

    test('anyone can block it with Duke', () {
      final game = setup([
        [duke, duke],
        [captain, captain],
        [duke, captain],
      ]);
      game.declareAction('a', ActionType.foreignAid);
      game.block('c', duke);
      expect(() => game.block('b', duke), throwsRule);
      game.pass('a');
      game.pass('b');
      expect(game.player('a').coins, 2);
      expect(game.currentPlayer.id, 'b');
    });

    test('only Duke blocks it', () {
      final game = setup([
        [duke, duke],
        [captain, captain],
      ]);
      game.declareAction('a', ActionType.foreignAid);
      expect(() => game.block('b', contessa), throwsRule);
    });

    test('a bluffed block that is challenged lets the action through', () {
      final game = setup([
        [duke, duke],
        [captain, contessa],
        [duke, duke],
      ]);
      game.declareAction('a', ActionType.foreignAid);
      game.block('b', duke);
      game.challenge('a');
      game.loseInfluence('b', contessa);
      expect(game.player('a').coins, 4);
      expect(game.currentPlayer.id, 'b');
    });

    test('a true block that is challenged costs the challenger a card', () {
      final game = setup([
        [captain, contessa],
        [duke, assassin],
        [duke, duke],
      ]);
      game.declareAction('a', ActionType.foreignAid);
      game.block('b', duke);
      game.challenge('a');
      game.loseInfluence('a', captain);
      expect(game.player('a').coins, 2);
      expect(game.player('b').hiddenCharacters, hasLength(2));
      expect(game.currentPlayer.id, 'b');
    });
  });

  group('challenging a character claim', () {
    test('an unchallenged tax gives 3 coins', () {
      final game = setup([
        [captain, captain],
        [captain, captain],
        [duke, duke],
      ]);
      game.declareAction('a', ActionType.tax);
      expect(game.phase, isA<AwaitingActionChallenge>());
      game.pass('b');
      game.pass('c');
      expect(game.player('a').coins, 5);
    });

    test('the actor cannot respond to their own claim', () {
      final game = setup([
        [duke, duke],
        [captain, captain],
      ]);
      game.declareAction('a', ActionType.tax);
      expect(() => game.pass('a'), throwsRule);
      expect(() => game.challenge('a'), throwsRule);
    });

    test('a player cannot pass twice', () {
      final game = setup([
        [duke, duke],
        [captain, captain],
        [duke, duke],
      ]);
      game.declareAction('a', ActionType.tax);
      game.pass('b');
      expect(() => game.pass('b'), throwsRule);
    });

    test(
      'proving the claim: challenger loses a card, actor swaps the card',
      () {
        final game = setup([
          [duke, captain],
          [contessa, assassin],
          [duke, duke],
        ]);
        final deckSize = game.deckSize;
        game.declareAction('a', ActionType.tax);
        game.challenge('b');

        game.loseInfluence('b', contessa);
        expect(game.player('b').hiddenCharacters, [assassin]);
        expect(game.player('a').coins, 5);
        expect(game.player('a').hiddenCharacters, hasLength(2));
        expect(game.deckSize, deckSize);
        expect(game.currentPlayer.id, 'b');
      },
    );

    test('a caught bluff loses a card and the action fails', () {
      final game = setup([
        [captain, contessa],
        [duke, duke],
        [duke, duke],
      ]);
      game.declareAction('a', ActionType.tax);
      game.challenge('c');
      game.loseInfluence('a', captain);
      expect(game.player('a').coins, 2);
      expect(game.player('a').hiddenCharacters, [contessa]);
      expect(game.currentPlayer.id, 'b');
    });
  });

  group('assassinate', () {
    test('a caught bluff refunds the 3 coins', () {
      final game = setup(
        [
          [captain, contessa],
          [duke, duke],
        ],
        coins: [3, 2],
      );
      game.declareAction('a', ActionType.assassinate, targetId: 'b');
      expect(game.player('a').coins, 0);
      game.challenge('b');
      game.loseInfluence('a', captain);
      expect(game.player('a').coins, 3);
      expect(game.player('b').hiddenCharacters, hasLength(2));
    });

    test('blocked by Contessa: coins stay spent, target keeps both cards', () {
      final game = setup(
        [
          [assassin, duke],
          [contessa, duke],
          [duke, duke],
        ],
        coins: [3, 2, 2],
      );
      game.declareAction('a', ActionType.assassinate, targetId: 'b');
      game.pass('b');
      game.pass('c');
      expect(
        () => game.block('c', contessa),
        throwsRule,
        reason: 'only the target may block',
      );
      game.block('b', contessa);
      game.pass('a');
      game.pass('c');
      expect(game.player('a').coins, 0);
      expect(game.player('b').hiddenCharacters, hasLength(2));
      expect(game.currentPlayer.id, 'b');
    });

    test('a target who wrongly challenges loses both cards', () {
      final game = setup(
        [
          [assassin, duke],
          [captain, duke],
          [duke, duke],
        ],
        coins: [3, 2, 2],
      );
      game.declareAction('a', ActionType.assassinate, targetId: 'b');
      game.challenge('b');
      game.loseInfluence('b', captain);
      game.pass('b'); // declines to block with the last card
      expect(game.player('b').isAlive, isFalse);
      expect(game.currentPlayer.id, 'c', reason: 'b is skipped');
    });

    test('the action fizzles if the target died from their own challenge', () {
      final game = setup(
        [
          [assassin, duke],
          [captain],
          [duke, duke],
        ],
        coins: [3, 2, 2],
      );
      game.declareAction('a', ActionType.assassinate, targetId: 'b');
      game.challenge('b');
      expect(game.player('b').isAlive, isFalse);
      expect(game.player('a').coins, 0);
      expect(game.currentPlayer.id, 'c');
    });
  });

  group('steal', () {
    test('takes 2 coins', () {
      final game = setup(
        [
          [captain, duke],
          [duke, duke],
        ],
        coins: [2, 5],
      );
      game.declareAction('a', ActionType.steal, targetId: 'b');
      game.pass('b');
      game.pass('b');
      expect(game.player('a').coins, 4);
      expect(game.player('b').coins, 3);
    });

    test('takes only what the target has', () {
      final game = setup(
        [
          [captain, duke],
          [duke, duke],
        ],
        coins: [2, 1],
      );
      game.declareAction('a', ActionType.steal, targetId: 'b');
      game.pass('b');
      game.pass('b');
      expect(game.player('a').coins, 3);
      expect(game.player('b').coins, 0);
    });

    test('can be blocked by Captain or Ambassador, not Duke', () {
      final game = setup([
        [captain, duke],
        [duke, duke],
      ]);
      game.declareAction('a', ActionType.steal, targetId: 'b');
      game.pass('b');
      expect(() => game.block('b', duke), throwsRule);
      game.block('b', ambassador);
      expect(game.phase, isA<AwaitingBlockChallenge>());
    });
  });

  group('exchange', () {
    test('offers hand plus 2 cards and returns the rest to the deck', () {
      final game = setup(
        [
          [ambassador, duke],
          [duke, duke],
        ],
        deck: [captain, contessa, assassin],
      );
      game.declareAction('a', ActionType.exchange);
      game.pass('b');

      final phase = game.phase as AwaitingExchange;
      expect(phase.options, [ambassador, duke, captain, contessa]);
      expect(phase.keepCount, 2);
      expect(game.deckSize, 1);

      expect(() => game.exchange('a', [captain, captain]), throwsRule);
      expect(() => game.exchange('a', [captain]), throwsRule);
      expect(() => game.exchange('b', [captain, contessa]), throwsRule);

      game.exchange('a', [captain, contessa]);
      expect(game.player('a').hiddenCharacters, [captain, contessa]);
      expect(game.deckSize, 3);
      expect(game.currentPlayer.id, 'b');
    });

    test('a player with one card keeps one', () {
      final game = setup(
        [
          [ambassador],
          [duke, duke],
        ],
        deck: [captain, contessa],
      );
      game.declareAction('a', ActionType.exchange);
      game.pass('b');
      expect((game.phase as AwaitingExchange).keepCount, 1);
      game.exchange('a', [contessa]);
      expect(game.player('a').hiddenCharacters, [contessa]);
    });
  });

  group('game over', () {
    test('the last player with influence wins', () {
      final game = setup(
        [
          [duke, duke],
          [captain],
        ],
        coins: [7, 2],
      );
      game.declareAction('a', ActionType.coup, targetId: 'b');
      expect((game.phase as GameOver).winnerId, 'a');
      expect(() => game.declareAction('b', ActionType.income), throwsRule);
    });

    test('a bluffer can lose the game on their own turn', () {
      final game = setup([
        [captain],
        [duke, duke],
      ]);
      game.declareAction('a', ActionType.tax);
      game.challenge('b');
      expect((game.phase as GameOver).winnerId, 'b');
    });
  });
}
