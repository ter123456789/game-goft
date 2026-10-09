/// A request that is well-formed but not allowed, separate from
/// [GameRuleException], which covers illegal moves inside a game.
class AppException implements Exception {
  const AppException.notFound(this.message) : kind = AppErrorKind.notFound;
  const AppException.forbidden(this.message) : kind = AppErrorKind.forbidden;
  const AppException.conflict(this.message) : kind = AppErrorKind.conflict;

  final AppErrorKind kind;
  final String message;

  @override
  String toString() => 'AppException(${kind.name}): $message';
}

enum AppErrorKind { notFound, forbidden, conflict }
