import 'action_type.dart';
import 'character.dart';
import 'coup_game.dart';

/// A move a player sends to the server: the wire format shared by the app
/// and the server. The player is always the authenticated user, so it is not
/// part of the command.
sealed class GameCommand {
  const GameCommand();

  /// Parses [toJson] output. Throws [FormatException] on anything else.
  factory GameCommand.fromJson(Map<String, Object?> json) => switch (json) {
    {'type': 'declareAction', 'action': final action} => DeclareActionCommand(
      _enum(ActionType.values, action),
      targetId: switch (json['targetId']) {
        final String id => id,
        null => null,
        _ => throw const FormatException('targetId must be a string'),
      },
    ),
    {'type': 'challenge'} => const ChallengeCommand(),
    {'type': 'pass'} => const PassCommand(),
    {'type': 'block', 'character': final c} => BlockCommand(
      _enum(Character.values, c),
    ),
    {'type': 'loseInfluence', 'character': final c} => LoseInfluenceCommand(
      _enum(Character.values, c),
    ),
    {'type': 'exchange', 'keep': List keep} => ExchangeCommand([
      for (final c in keep) _enum(Character.values, c),
    ]),
    _ => throw const FormatException('Unknown command'),
  };

  void applyTo(CoupGame game, String playerId);

  Map<String, Object?> toJson();
}

final class DeclareActionCommand extends GameCommand {
  const DeclareActionCommand(this.type, {this.targetId});

  final ActionType type;
  final String? targetId;

  @override
  void applyTo(CoupGame game, String playerId) =>
      game.declareAction(playerId, type, targetId: targetId);

  @override
  Map<String, Object?> toJson() => {
    'type': 'declareAction',
    'action': type.name,
    'targetId': ?targetId,
  };
}

final class ChallengeCommand extends GameCommand {
  const ChallengeCommand();

  @override
  void applyTo(CoupGame game, String playerId) => game.challenge(playerId);

  @override
  Map<String, Object?> toJson() => {'type': 'challenge'};
}

final class PassCommand extends GameCommand {
  const PassCommand();

  @override
  void applyTo(CoupGame game, String playerId) => game.pass(playerId);

  @override
  Map<String, Object?> toJson() => {'type': 'pass'};
}

final class BlockCommand extends GameCommand {
  const BlockCommand(this.character);

  final Character character;

  @override
  void applyTo(CoupGame game, String playerId) =>
      game.block(playerId, character);

  @override
  Map<String, Object?> toJson() => {
    'type': 'block',
    'character': character.name,
  };
}

final class LoseInfluenceCommand extends GameCommand {
  const LoseInfluenceCommand(this.character);

  final Character character;

  @override
  void applyTo(CoupGame game, String playerId) =>
      game.loseInfluence(playerId, character);

  @override
  Map<String, Object?> toJson() => {
    'type': 'loseInfluence',
    'character': character.name,
  };
}

final class ExchangeCommand extends GameCommand {
  const ExchangeCommand(this.keep);

  final List<Character> keep;

  @override
  void applyTo(CoupGame game, String playerId) => game.exchange(playerId, keep);

  @override
  Map<String, Object?> toJson() => {
    'type': 'exchange',
    'keep': [for (final c in keep) c.name],
  };
}

T _enum<T extends Enum>(List<T> values, Object? name) =>
    values.asNameMap()[name] ??
    (throw FormatException('Unknown ${T.toString()}: $name'));
