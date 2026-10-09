import 'package:coup_domain/coup_domain.dart';

/// What the signed-in player is being asked to do right now.
sealed class TurnPrompt {
  const TurnPrompt();
}

/// It is my turn. Bluffing is allowed, so every action is offered; [hand]
/// is there to hint which claims are true.
final class ChooseAction extends TurnPrompt {
  const ChooseAction({
    required this.coins,
    required this.targets,
    required this.hand,
  });

  final int coins;

  /// Living opponents.
  final List<String> targets;
  final List<Character> hand;

  bool get mustCoup => coins >= mustCoupAt;

  bool canAfford(ActionType type) => coins >= type.cost;

  bool isAllowed(ActionType type) =>
      canAfford(type) && (!mustCoup || type == ActionType.coup);
}

/// Someone claimed a character for an action: challenge or pass.
final class ChallengeAction extends TurnPrompt {
  const ChallengeAction(this.action);

  final PendingAction action;
}

/// I may block the action (as its target, or anyone for foreign aid).
final class BlockOrPass extends TurnPrompt {
  const BlockOrPass(this.action, this.hand);

  final PendingAction action;
  final List<Character> hand;

  List<Character> get blockers => action.type.blockedBy.toList();
}

/// Someone blocked: challenge the block or pass.
final class ChallengeBlock extends TurnPrompt {
  const ChallengeBlock(this.action, this.block);

  final PendingAction action;
  final Block block;
}

final class ChooseCardToLose extends TurnPrompt {
  const ChooseCardToLose(this.hand);

  final List<Character> hand;
}

final class ChooseCardsToKeep extends TurnPrompt {
  const ChooseCardsToKeep(this.options, this.keepCount);

  final List<Character> options;
  final int keepCount;
}

/// Nothing for me to do; waiting for [playerIds].
final class WaitForOthers extends TurnPrompt {
  const WaitForOthers(this.playerIds);

  final Set<String> playerIds;
}

final class GameFinished extends TurnPrompt {
  const GameFinished(this.winnerId);

  final String winnerId;
}

/// Works out the prompt for player [me]. [hand] must be from the same
/// revision as [view]; pass null while it is still syncing.
TurnPrompt promptFor(String me, PublicGameView view, PrivateView? hand) {
  final phase = view.phase;
  if (phase is GameOver) return GameFinished(phase.winnerId);
  if (!view.waitingFor.contains(me)) return WaitForOthers(view.waitingFor);
  if (hand == null) return WaitForOthers(const {});

  return switch (phase) {
    AwaitingAction() => ChooseAction(
      coins: view.players.firstWhere((p) => p.id == me).coins,
      targets: [
        for (final p in view.players)
          if (p.isAlive && p.id != me) p.id,
      ],
      hand: hand.hand,
    ),
    AwaitingActionChallenge(:final action) => ChallengeAction(action),
    AwaitingBlock(:final action) => BlockOrPass(action, hand.hand),
    AwaitingBlockChallenge(:final action, :final block) => ChallengeBlock(
      action,
      block,
    ),
    AwaitingInfluenceLoss() => ChooseCardToLose(hand.hand),
    AwaitingExchange(:final keepCount) => ChooseCardsToKeep(
      hand.exchangeOptions ?? const [],
      keepCount,
    ),
    GameOver(:final winnerId) => GameFinished(winnerId),
  };
}
