import 'package:coup_domain/coup_domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_goft/application/turn_prompt.dart';

CoupGame game({List<int> coins = const [2, 2, 2]}) => CoupGame.fromPosition(
  players: [
    (id: 'a', hand: [Character.duke, Character.captain], coins: coins[0]),
    (id: 'b', hand: [Character.contessa, Character.duke], coins: coins[1]),
    (
      id: 'c',
      hand: [Character.assassin, Character.ambassador],
      coins: coins[2],
    ),
  ],
  deck: [Character.captain, Character.contessa],
);

TurnPrompt promptOf(CoupGame g, String me, {bool handSynced = true}) =>
    promptFor(me, g.publicView(), handSynced ? g.privateView(me) : null);

void main() {
  test('the current player chooses an action', () {
    final prompt = promptOf(game(), 'a') as ChooseAction;
    expect(prompt.targets, ['b', 'c']);
    expect(prompt.hand, [Character.duke, Character.captain]);
    expect(prompt.isAllowed(ActionType.income), isTrue);
    expect(prompt.isAllowed(ActionType.coup), isFalse, reason: 'needs 7');
  });

  test('with 10 coins only coup is allowed', () {
    final prompt = promptOf(game(coins: [10, 2, 2]), 'a') as ChooseAction;
    expect(prompt.mustCoup, isTrue);
    expect(prompt.isAllowed(ActionType.coup), isTrue);
    expect(prompt.isAllowed(ActionType.tax), isFalse);
  });

  test('others wait for the current player', () {
    final prompt = promptOf(game(), 'b') as WaitForOthers;
    expect(prompt.playerIds, {'a'});
  });

  test('a claim asks everyone else to challenge or pass', () {
    final g = game()..declareAction('a', ActionType.tax);
    expect(promptOf(g, 'b'), isA<ChallengeAction>());
    expect(promptOf(g, 'c'), isA<ChallengeAction>());
    expect(promptOf(g, 'a'), isA<WaitForOthers>());
  });

  test('only the target may block a steal', () {
    final g = game()
      ..declareAction('a', ActionType.steal, targetId: 'b')
      ..pass('b')
      ..pass('c');
    final prompt = promptOf(g, 'b') as BlockOrPass;
    expect(
      prompt.blockers,
      unorderedEquals([Character.captain, Character.ambassador]),
    );
    expect(promptOf(g, 'c'), isA<WaitForOthers>());
  });

  test('losing a card and exchanging show the right cards', () {
    final coup = game(coins: [7, 2, 2])
      ..declareAction('a', ActionType.coup, targetId: 'c');
    expect((promptOf(coup, 'c') as ChooseCardToLose).hand, [
      Character.assassin,
      Character.ambassador,
    ]);

    final exchange = game()
      ..declareAction('a', ActionType.exchange)
      ..pass('b')
      ..pass('c');
    final prompt = promptOf(exchange, 'a') as ChooseCardsToKeep;
    expect(prompt.options, hasLength(4));
    expect(prompt.keepCount, 2);
  });

  test('waits instead of guessing while the hand is out of sync', () {
    expect(promptOf(game(), 'a', handSynced: false), isA<WaitForOthers>());
  });

  test('game over names the winner', () {
    final g = CoupGame.fromPosition(
      players: [
        (id: 'a', hand: [Character.duke], coins: 7),
        (id: 'b', hand: [Character.captain], coins: 2),
      ],
      deck: [],
    )..declareAction('a', ActionType.coup, targetId: 'b');
    expect((promptOf(g, 'b') as GameFinished).winnerId, 'a');
  });
}
