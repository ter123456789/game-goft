import 'character.dart';

/// Every action a player can take on their turn.
enum ActionType {
  /// +1 coin. Cannot be challenged or blocked.
  income(),

  /// +2 coins. Any player may block by claiming Duke.
  foreignAid(blockedBy: {Character.duke}),

  /// Pay 7 coins; the target loses one influence. Cannot be blocked.
  coup(cost: 7, targeted: true),

  /// Duke: +3 coins.
  tax(claim: Character.duke),

  /// Assassin: pay 3 coins; the target loses one influence.
  assassinate(
    cost: 3,
    claim: Character.assassin,
    targeted: true,
    blockedBy: {Character.contessa},
  ),

  /// Captain: take up to 2 coins from the target.
  steal(
    claim: Character.captain,
    targeted: true,
    blockedBy: {Character.captain, Character.ambassador},
  ),

  /// Ambassador: draw 2 cards from the court deck, then return 2.
  exchange(claim: Character.ambassador);

  const ActionType({
    this.cost = 0,
    this.claim,
    this.targeted = false,
    this.blockedBy = const {},
  });

  /// Coins paid when the action is declared.
  final int cost;

  /// The character the actor claims to hold, or null for general actions.
  final Character? claim;

  final bool targeted;

  /// Characters that can block this action. For targeted actions only the
  /// target may block; for foreign aid anyone may.
  final Set<Character> blockedBy;

  bool get isChallengeable => claim != null;
  bool get isBlockable => blockedBy.isNotEmpty;
}
