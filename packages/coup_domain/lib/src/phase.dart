part of 'coup_game.dart';

/// An action that has been declared but not yet resolved.
class PendingAction {
  const PendingAction({
    required this.actorId,
    required this.type,
    this.targetId,
  });

  final String actorId;
  final ActionType type;
  final String? targetId;
}

/// A claim to block a [PendingAction] with [character].
class Block {
  const Block(this.blockerId, this.character);

  final String blockerId;
  final Character character;
}

/// What happens once a player has chosen which influence to lose.
enum AfterLoss {
  /// The actor's claim was proven; continue to the block window or resolve.
  claimStands,

  /// The actor was caught bluffing; refund the cost and end the turn.
  actionFailed,

  /// The blocker was caught bluffing; the action goes through.
  resolveAction,

  endTurn,
}

/// Where the turn is. Each phase says whose input the game is waiting for.
sealed class Phase {
  const Phase();
}

/// The current player must declare an action.
final class AwaitingAction extends Phase {
  const AwaitingAction();
}

/// Every other living player must [CoupGame.challenge] or [CoupGame.pass]
/// the actor's character claim.
final class AwaitingActionChallenge extends Phase {
  const AwaitingActionChallenge(this.action, {this.passed = const {}});

  final PendingAction action;
  final Set<String> passed;
}

/// Eligible blockers must [CoupGame.block] or [CoupGame.pass].
final class AwaitingBlock extends Phase {
  const AwaitingBlock(this.action, {this.passed = const {}});

  final PendingAction action;
  final Set<String> passed;
}

/// Every living player except the blocker must challenge or pass the block.
final class AwaitingBlockChallenge extends Phase {
  const AwaitingBlockChallenge(
    this.action,
    this.block, {
    this.passed = const {},
  });

  final PendingAction action;
  final Block block;
  final Set<String> passed;
}

/// [playerId] must choose a card to reveal. Skipped automatically when the
/// player has only one card left.
final class AwaitingInfluenceLoss extends Phase {
  const AwaitingInfluenceLoss(this.playerId, this.action, this.then);

  final String playerId;
  final PendingAction action;
  final AfterLoss then;
}

/// The Ambassador player must keep [keepCount] of [options].
final class AwaitingExchange extends Phase {
  const AwaitingExchange(this.action, this.options, this.keepCount);

  final PendingAction action;
  final List<Character> options;
  final int keepCount;
}

final class GameOver extends Phase {
  const GameOver(this.winnerId);

  final String winnerId;
}
