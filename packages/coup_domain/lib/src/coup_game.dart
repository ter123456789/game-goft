import 'dart:math';

import 'action_type.dart';
import 'character.dart';
import 'game_rule_exception.dart';

part 'coup_game_json.dart';
part 'game_view.dart';
part 'phase.dart';
part 'player.dart';

/// Players holding this many coins at the start of their turn must coup.
const mustCoupAt = 10;

/// The rules of Coup as a state machine.
///
/// Each command method validates the move against the current [phase],
/// throws [GameRuleException] if it is illegal, and otherwise advances the
/// game. The state holds every player's hidden cards, so it belongs on a
/// trusted side (server or host); clients should only see a filtered view.
class CoupGame {
  CoupGame._(this._players, this._deck, this._random, this._current);

  factory CoupGame.start(List<String> playerIds, {Random? random}) {
    if (playerIds.length < 2 || playerIds.length > 6) {
      throw const GameRuleException('Coup needs 2 to 6 players');
    }
    if (playerIds.toSet().length != playerIds.length) {
      throw const GameRuleException('Player ids must be unique');
    }
    final rng = random ?? Random();
    final deck = [for (final c in Character.values) ...List.filled(3, c)]
      ..shuffle(rng);
    // Two-player variant: the starting player begins with only 1 coin.
    final players = [
      for (final (i, id) in playerIds.indexed)
        Player._(
          id,
          coins: playerIds.length == 2 && i == 0 ? 1 : 2,
          hand: [deck.removeLast(), deck.removeLast()],
        ),
    ];
    return CoupGame._(players, deck, rng, 0);
  }

  /// Builds a game from a known position, for tests and restoring saves.
  /// Cards are drawn from the front of [deck].
  factory CoupGame.fromPosition({
    required List<({String id, List<Character> hand, int coins})> players,
    required List<Character> deck,
    int currentPlayer = 0,
    Random? random,
  }) => CoupGame._(
    [for (final p in players) Player._(p.id, coins: p.coins, hand: p.hand)],
    [...deck],
    random ?? Random(),
    currentPlayer,
  );

  /// Restores a game saved with [toJson]. Throws [FormatException] if
  /// [json] is not a valid save.
  factory CoupGame.fromJson(Map<String, Object?> json, {Random? random}) =>
      _gameFromJson(json, random ?? Random());

  final List<Player> _players;
  final List<Character> _deck;
  final Random _random;
  int _current;
  Phase _currentPhase = const AwaitingAction();
  int _revision = 0;

  Phase get phase => _currentPhase;

  /// Increases every time the phase changes. A server can store it with a
  /// timer and skip [timeOut] if the game has moved on, or use it for
  /// optimistic locking when saving.
  int get revision => _revision;

  set _phase(Phase phase) {
    _currentPhase = phase;
    _revision++;
  }

  Phase get _phase => _currentPhase;
  List<Player> get players => List.unmodifiable(_players);
  Player get currentPlayer => _players[_current];
  int get deckSize => _deck.length;

  Player player(String id) => _players.firstWhere(
    (p) => p.id == id,
    orElse: () => throw GameRuleException('Unknown player $id'),
  );

  /// The full state, including every hidden card and the deck order.
  /// Keep it on the server; never send it to clients as-is.
  Map<String, Object?> toJson() => _gameToJson(this);

  /// What everyone may see: coins, revealed cards, card counts and the phase.
  PublicGameView publicView() => _publicView(this);

  /// What only [playerId] may see: their hand and any exchange options.
  PrivateView privateView(String playerId) => _privateView(this, playerId);

  /// Players whose input the game is waiting for right now.
  Set<String> get waitingFor => switch (_phase) {
    AwaitingAction() => {currentPlayer.id},
    AwaitingActionChallenge(:final action, :final passed) => _othersAlive(
      action.actorId,
    ).difference(passed),
    AwaitingBlock(:final action, :final passed) => _blockersOf(
      action,
    ).difference(passed),
    AwaitingBlockChallenge(:final block, :final passed) => _othersAlive(
      block.blockerId,
    ).difference(passed),
    AwaitingInfluenceLoss(:final playerId) => {playerId},
    AwaitingExchange(:final action) => {action.actorId},
    GameOver() => const {},
  };

  // ---------------------------------------------------------------- commands

  void declareAction(String actorId, ActionType type, {String? targetId}) {
    _expect<AwaitingAction>();
    final actor = player(actorId);
    if (actor != currentPlayer) {
      throw GameRuleException("It is not $actorId's turn");
    }
    if (actor.coins >= mustCoupAt && type != ActionType.coup) {
      throw const GameRuleException('With 10 or more coins you must coup');
    }
    if (actor.coins < type.cost) {
      throw GameRuleException('${type.name} costs ${type.cost} coins');
    }
    if (type.targeted) {
      if (targetId == null) {
        throw GameRuleException('${type.name} needs a target');
      }
      final target = player(targetId);
      if (target == actor || !target.isAlive) {
        throw GameRuleException('$targetId is not a valid target');
      }
    } else if (targetId != null) {
      throw GameRuleException('${type.name} does not take a target');
    }

    actor._coins -= type.cost;
    final action = PendingAction(
      actorId: actorId,
      type: type,
      targetId: targetId,
    );
    if (type.isChallengeable) {
      _phase = AwaitingActionChallenge(action);
    } else {
      _afterClaimStands(action);
    }
  }

  /// Declines to challenge or block in the current response window.
  void pass(String playerId) {
    switch (_phase) {
      case AwaitingActionChallenge(:final action, :final passed):
        final eligible = _othersAlive(action.actorId);
        final now = _respond(playerId, eligible, passed);
        if (now.containsAll(eligible)) {
          _afterClaimStands(action);
        } else {
          _phase = AwaitingActionChallenge(action, passed: now);
        }
      case AwaitingBlock(:final action, :final passed):
        final eligible = _blockersOf(action);
        final now = _respond(playerId, eligible, passed);
        if (now.containsAll(eligible)) {
          _resolve(action);
        } else {
          _phase = AwaitingBlock(action, passed: now);
        }
      case AwaitingBlockChallenge(:final action, :final block, :final passed):
        final eligible = _othersAlive(block.blockerId);
        final now = _respond(playerId, eligible, passed);
        if (now.containsAll(eligible)) {
          _endTurn(); // The block stands.
        } else {
          _phase = AwaitingBlockChallenge(action, block, passed: now);
        }
      default:
        throw const GameRuleException('There is nothing to pass on');
    }
  }

  /// Makes the default move for everyone in [waitingFor], for when their
  /// time runs out: pass on challenges and blocks, take income (or coup the
  /// next player when holding 10+ coins), lose the first hidden card, and
  /// keep the original hand when exchanging.
  void timeOut() {
    switch (_phase) {
      case AwaitingAction():
        final actor = currentPlayer;
        if (actor.coins >= mustCoupAt) {
          declareAction(
            actor.id,
            ActionType.coup,
            targetId: _nextAliveAfter(_current).id,
          );
        } else {
          declareAction(actor.id, ActionType.income);
        }
      case AwaitingActionChallenge() ||
          AwaitingBlock() ||
          AwaitingBlockChallenge():
        for (final id in waitingFor) {
          pass(id);
        }
      case AwaitingInfluenceLoss(:final playerId):
        loseInfluence(playerId, player(playerId).hiddenCharacters.first);
      case AwaitingExchange(:final action, :final options, :final keepCount):
        // Options start with the actor's own hand.
        exchange(action.actorId, options.take(keepCount).toList());
      case GameOver():
        throw const GameRuleException('The game is over');
    }
  }

  void challenge(String challengerId) {
    switch (_phase) {
      case AwaitingActionChallenge(:final action, :final passed):
        _respond(challengerId, _othersAlive(action.actorId), passed);
        final actor = player(action.actorId);
        final claim = action.type.claim!;
        if (actor.hasHidden(claim)) {
          _replaceProvenCard(actor, claim);
          _requireLoss(challengerId, action, AfterLoss.claimStands);
        } else {
          _requireLoss(actor.id, action, AfterLoss.actionFailed);
        }
      case AwaitingBlockChallenge(:final action, :final block, :final passed):
        _respond(challengerId, _othersAlive(block.blockerId), passed);
        final blocker = player(block.blockerId);
        if (blocker.hasHidden(block.character)) {
          _replaceProvenCard(blocker, block.character);
          _requireLoss(challengerId, action, AfterLoss.endTurn);
        } else {
          _requireLoss(blocker.id, action, AfterLoss.resolveAction);
        }
      default:
        throw const GameRuleException('There is no claim to challenge');
    }
  }

  void block(String blockerId, Character character) {
    final phase = _expect<AwaitingBlock>();
    _respond(blockerId, _blockersOf(phase.action), phase.passed);
    if (!phase.action.type.blockedBy.contains(character)) {
      throw GameRuleException(
        '${character.name} cannot block ${phase.action.type.name}',
      );
    }
    _phase = AwaitingBlockChallenge(phase.action, Block(blockerId, character));
  }

  void loseInfluence(String playerId, Character character) {
    final phase = _expect<AwaitingInfluenceLoss>();
    if (phase.playerId != playerId) {
      throw GameRuleException('$playerId is not the one losing influence');
    }
    final p = player(playerId);
    if (!p.hasHidden(character)) {
      throw GameRuleException('$playerId has no hidden ${character.name}');
    }
    p._reveal(character);
    _continueAfterLoss(phase.action, phase.then);
  }

  void exchange(String playerId, List<Character> keep) {
    final phase = _expect<AwaitingExchange>();
    if (phase.action.actorId != playerId) {
      throw GameRuleException('$playerId is not exchanging');
    }
    if (keep.length != phase.keepCount) {
      throw GameRuleException('Keep exactly ${phase.keepCount} cards');
    }
    final returned = [...phase.options];
    for (final c in keep) {
      if (!returned.remove(c)) {
        throw GameRuleException('${c.name} is not among the offered cards');
      }
    }
    player(playerId)._replaceHidden(keep);
    _deck
      ..addAll(returned)
      ..shuffle(_random);
    _endTurn();
  }

  // ------------------------------------------------------------- transitions

  void _afterClaimStands(PendingAction action) {
    if (action.type.isBlockable && _targetStillAlive(action)) {
      _phase = AwaitingBlock(action);
    } else {
      _resolve(action);
    }
  }

  void _resolve(PendingAction action) {
    // The target may have died losing a challenge; the action then fizzles.
    if (!_targetStillAlive(action)) return _endTurn();

    final actor = player(action.actorId);
    switch (action.type) {
      case ActionType.income:
        actor._coins += 1;
      case ActionType.foreignAid:
        actor._coins += 2;
      case ActionType.tax:
        actor._coins += 3;
      case ActionType.steal:
        final target = player(action.targetId!);
        final amount = min(2, target.coins);
        target._coins -= amount;
        actor._coins += amount;
      case ActionType.coup || ActionType.assassinate:
        return _requireLoss(action.targetId!, action, AfterLoss.endTurn);
      case ActionType.exchange:
        final hand = actor.hiddenCharacters;
        _phase = AwaitingExchange(action, [
          ...hand,
          _draw(),
          _draw(),
        ], hand.length);
        return;
    }
    _endTurn();
  }

  void _requireLoss(String playerId, PendingAction action, AfterLoss then) {
    final hidden = player(playerId).hiddenCharacters;
    if (hidden.length == 1) {
      player(playerId)._reveal(hidden.single);
      _continueAfterLoss(action, then);
    } else {
      _phase = AwaitingInfluenceLoss(playerId, action, then);
    }
  }

  void _continueAfterLoss(PendingAction action, AfterLoss then) {
    final alive = _players.where((p) => p.isAlive).toList();
    if (alive.length == 1) {
      _phase = GameOver(alive.single.id);
      return;
    }
    switch (then) {
      case AfterLoss.claimStands:
        _afterClaimStands(action);
      case AfterLoss.actionFailed:
        // A failed challenge returns the coins paid (e.g. for assassinate).
        player(action.actorId)._coins += action.type.cost;
        _endTurn();
      case AfterLoss.resolveAction:
        _resolve(action);
      case AfterLoss.endTurn:
        _endTurn();
    }
  }

  void _endTurn() {
    _current = _players.indexOf(_nextAliveAfter(_current));
    _phase = const AwaitingAction();
  }

  Player _nextAliveAfter(int index) {
    for (var i = 1; i < _players.length; i++) {
      final p = _players[(index + i) % _players.length];
      if (p.isAlive) return p;
    }
    throw StateError('No other player is alive');
  }

  // ----------------------------------------------------------------- helpers

  T _expect<T extends Phase>() {
    final phase = _phase;
    if (phase is! T) {
      throw GameRuleException(
        'Expected $T but the game is in ${phase.runtimeType}',
      );
    }
    return phase;
  }

  Set<String> _othersAlive(String excludedId) => {
    for (final p in _players)
      if (p.isAlive && p.id != excludedId) p.id,
  };

  Set<String> _blockersOf(PendingAction action) =>
      action.type.targeted ? {action.targetId!} : _othersAlive(action.actorId);

  /// Validates that [playerId] may still respond and returns the new set of
  /// players who have responded.
  Set<String> _respond(
    String playerId,
    Set<String> eligible,
    Set<String> passed,
  ) {
    player(playerId);
    if (!eligible.contains(playerId)) {
      throw GameRuleException('$playerId cannot respond to this');
    }
    if (passed.contains(playerId)) {
      throw GameRuleException('$playerId has already passed');
    }
    return {...passed, playerId};
  }

  bool _targetStillAlive(PendingAction action) =>
      action.targetId == null || player(action.targetId!).isAlive;

  /// A player who proves a claim shuffles that card back and draws a new one.
  void _replaceProvenCard(Player p, Character character) {
    _deck
      ..add(character)
      ..shuffle(_random);
    p._swapHidden(character, _draw());
  }

  Character _draw() => _deck.removeAt(0);
}
