/// Thrown when a command breaks the rules or arrives in the wrong phase.
class GameRuleException implements Exception {
  const GameRuleException(this.message);

  final String message;

  @override
  String toString() => 'GameRuleException: $message';
}
