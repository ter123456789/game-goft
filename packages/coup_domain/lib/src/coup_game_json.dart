part of 'coup_game.dart';

/// Bump when the saved shape changes so old saves fail loudly.
const _jsonVersion = 1;

Map<String, Object?> _gameToJson(CoupGame game) => {
  'version': _jsonVersion,
  'players': [
    for (final p in game._players)
      {
        'id': p.id,
        'coins': p._coins,
        'influences': [
          for (final i in p._influences)
            {'character': i.character.name, 'revealed': i.revealed},
        ],
      },
  ],
  'deck': [for (final c in game._deck) c.name],
  'current': game._current,
  'revision': game._revision,
  'phase': _phaseToJson(game._phase),
};

Map<String, Object?> _phaseToJson(Phase phase) => switch (phase) {
  AwaitingAction() => {'type': 'awaitingAction'},
  AwaitingActionChallenge(:final action, :final passed) => {
    'type': 'awaitingActionChallenge',
    'action': _actionToJson(action),
    'passed': passed.toList(),
  },
  AwaitingBlock(:final action, :final passed) => {
    'type': 'awaitingBlock',
    'action': _actionToJson(action),
    'passed': passed.toList(),
  },
  AwaitingBlockChallenge(:final action, :final block, :final passed) => {
    'type': 'awaitingBlockChallenge',
    'action': _actionToJson(action),
    'block': {'blockerId': block.blockerId, 'character': block.character.name},
    'passed': passed.toList(),
  },
  AwaitingInfluenceLoss(:final playerId, :final action, :final then) => {
    'type': 'awaitingInfluenceLoss',
    'playerId': playerId,
    'action': _actionToJson(action),
    'then': then.name,
  },
  AwaitingExchange(:final action, :final options, :final keepCount) => {
    'type': 'awaitingExchange',
    'action': _actionToJson(action),
    'options': [for (final c in options) c.name],
    'keepCount': keepCount,
  },
  GameOver(:final winnerId) => {'type': 'gameOver', 'winnerId': winnerId},
};

Map<String, Object?> _actionToJson(PendingAction action) => {
  'actorId': action.actorId,
  'type': action.type.name,
  'targetId': ?action.targetId,
};

CoupGame _gameFromJson(Map<String, Object?> json, Random random) {
  if (json case {
    'version': _jsonVersion,
    'players': List players,
    'deck': List deck,
    'current': int current,
    'revision': int revision,
    'phase': final phase,
  } when current >= 0 && current < players.length) {
    return CoupGame._(
        [for (final p in players) _playerFromJson(p)],
        [for (final c in deck) _enum(Character.values, c)],
        random,
        current,
      )
      .._currentPhase = _phaseFromJson(phase)
      .._revision = revision;
  }
  throw _invalid('game', json);
}

Player _playerFromJson(Object? json) => switch (json) {
  {'id': String id, 'coins': int coins, 'influences': List influences} =>
    Player._restore(id, coins, [
      for (final i in influences) _influenceFromJson(i),
    ]),
  _ => throw _invalid('player', json),
};

Influence _influenceFromJson(Object? json) => switch (json) {
  {'character': final character, 'revealed': bool revealed} => Influence(
    _enum(Character.values, character),
    revealed: revealed,
  ),
  _ => throw _invalid('influence', json),
};

Phase _phaseFromJson(Object? json) => switch (json) {
  {'type': 'awaitingAction'} => const AwaitingAction(),
  {
    'type': 'awaitingActionChallenge',
    'action': final action,
    'passed': List passed,
  } =>
    AwaitingActionChallenge(_actionFromJson(action), passed: _ids(passed)),
  {'type': 'awaitingBlock', 'action': final action, 'passed': List passed} =>
    AwaitingBlock(_actionFromJson(action), passed: _ids(passed)),
  {
    'type': 'awaitingBlockChallenge',
    'action': final action,
    'block': {'blockerId': String blockerId, 'character': final character},
    'passed': List passed,
  } =>
    AwaitingBlockChallenge(
      _actionFromJson(action),
      Block(blockerId, _enum(Character.values, character)),
      passed: _ids(passed),
    ),
  {
    'type': 'awaitingInfluenceLoss',
    'playerId': String playerId,
    'action': final action,
    'then': final then,
  } =>
    AwaitingInfluenceLoss(
      playerId,
      _actionFromJson(action),
      _enum(AfterLoss.values, then),
    ),
  {
    'type': 'awaitingExchange',
    'action': final action,
    'options': List options,
    'keepCount': int keepCount,
  } =>
    AwaitingExchange(_actionFromJson(action), [
      for (final c in options) _enum(Character.values, c),
    ], keepCount),
  {'type': 'gameOver', 'winnerId': String winnerId} => GameOver(winnerId),
  _ => throw _invalid('phase', json),
};

PendingAction _actionFromJson(Object? json) => switch (json) {
  final Map<String, Object?> map &&
      {'actorId': String actorId, 'type': final type} =>
    PendingAction(
      actorId: actorId,
      type: _enum(ActionType.values, type),
      targetId: switch (map['targetId']) {
        final String id => id,
        null => null,
        final other => throw _invalid('targetId', other),
      },
    ),
  _ => throw _invalid('action', json),
};

Set<String> _ids(List json) => {
  for (final id in json)
    if (id is String) id else throw _invalid('player id', id),
};

T _enum<T extends Enum>(List<T> values, Object? name) =>
    values.asNameMap()[name] ?? (throw _invalid(T.toString(), name));

FormatException _invalid(String what, Object? value) =>
    FormatException('Invalid $what in saved Coup game', value);
