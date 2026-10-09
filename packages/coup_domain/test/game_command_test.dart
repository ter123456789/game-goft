import 'package:coup_domain/coup_domain.dart';
import 'package:test/test.dart';

void main() {
  const commands = <GameCommand>[
    DeclareActionCommand(ActionType.income),
    DeclareActionCommand(ActionType.steal, targetId: 'b'),
    ChallengeCommand(),
    PassCommand(),
    BlockCommand(Character.duke),
    LoseInfluenceCommand(Character.contessa),
    ExchangeCommand([Character.duke, Character.captain]),
  ];

  test('every command survives a JSON round trip', () {
    for (final command in commands) {
      final parsed = GameCommand.fromJson(command.toJson());
      expect(parsed.runtimeType, command.runtimeType);
      expect(parsed.toJson(), command.toJson());
    }
  });

  test('a parsed command applies to the game', () {
    final game = CoupGame.fromPosition(
      players: [
        (id: 'a', hand: [Character.duke], coins: 2),
        (id: 'b', hand: [Character.captain], coins: 2),
      ],
      deck: [],
    );
    GameCommand.fromJson({
      'type': 'declareAction',
      'action': 'income',
    }).applyTo(game, 'a');
    expect(game.player('a').coins, 3);
  });

  test('rejects malformed commands', () {
    for (final json in <Map<String, Object?>>[
      {},
      {'type': 'dance'},
      {'type': 'declareAction', 'action': 'fly'},
      {'type': 'declareAction', 'action': 'coup', 'targetId': 7},
      {'type': 'block', 'character': 'king'},
      {'type': 'block'},
      {'type': 'exchange', 'keep': 'duke'},
    ]) {
      expect(
        () => GameCommand.fromJson(json),
        throwsFormatException,
        reason: '$json',
      );
    }
  });
}
