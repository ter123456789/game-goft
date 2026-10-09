import 'app_exception.dart';

enum RoomStatus { lobby, playing, finished }

class Room {
  const Room({
    required this.id,
    required this.code,
    required this.hostId,
    required this.status,
  });

  final String id;
  final String code;
  final String hostId;
  final RoomStatus status;
}

class RoomPlayer {
  const RoomPlayer({
    required this.userId,
    required this.displayName,
    required this.seat,
  });

  final String userId;
  final String displayName;
  final int seat;
}

class SavedGame {
  const SavedGame({
    required this.state,
    required this.revision,
    required this.deadlineAt,
  });

  /// `CoupGame.toJson()` output.
  final Map<String, Object?> state;
  final int revision;
  final DateTime? deadlineAt;
}

/// Everything written after a move, saved atomically.
class GameUpdate {
  const GameUpdate({
    required this.roomId,
    required this.expectedRevision,
    required this.state,
    required this.revision,
    required this.deadlineAt,
    required this.publicView,
    required this.hands,
    required this.status,
  });

  final String roomId;

  /// The revision this update was computed from, or null for a new game.
  final int? expectedRevision;
  final Map<String, Object?> state;
  final int revision;
  final DateTime? deadlineAt;
  final Map<String, Object?> publicView;

  /// Player id -> that player's private view.
  final Map<String, Map<String, Object?>> hands;
  final RoomStatus status;
}

/// Thrown by [RoomRepository.createRoom] when the code is already in use.
class RoomCodeTaken implements Exception {
  const RoomCodeTaken();
}

/// Storage for rooms and games. Implemented by Supabase in production and
/// in memory for tests and local runs.
abstract interface class RoomRepository {
  /// Creates a room with the host in seat 0. Throws [RoomCodeTaken].
  Future<String> createRoom({
    required String hostId,
    required String displayName,
    required String code,
  });

  /// Adds the user to the next free seat; joining twice is a no-op.
  /// Throws [AppException] if the room is missing, started or full.
  Future<String> joinRoom({
    required String code,
    required String userId,
    required String displayName,
  });

  Future<Room?> findRoom(String roomId);

  /// Players ordered by seat.
  Future<List<RoomPlayer>> players(String roomId);

  Future<SavedGame?> loadGame(String roomId);

  /// Returns false, saving nothing, if [GameUpdate.expectedRevision] no
  /// longer matches (someone else saved first).
  Future<bool> saveGame(GameUpdate update);

  Future<List<String>> roomsPastDeadline(DateTime now);
}
