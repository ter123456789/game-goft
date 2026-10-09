import 'package:coup_domain/coup_domain.dart';

/// Sends requests to the game server. All game writes go through here.
abstract interface class GameApi {
  /// Pings the server, waiting while a sleeping host (e.g. Render's free
  /// plan) starts up. Returns whether it answered.
  Future<bool> wakeUp();

  Future<({String roomId, String code})> createRoom(String displayName);

  /// Returns the room id. Joining a room you are already in is fine.
  Future<String> joinRoom(String code, String displayName);

  Future<void> startGame(String roomId);

  Future<void> send(String roomId, GameCommand command);
}

/// The server refused a request; [message] is safe to show to the player.
class GameApiException implements Exception {
  const GameApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'GameApiException($statusCode): $message';
}
