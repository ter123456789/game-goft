import '../application/app_exception.dart';
import '../application/room_repository.dart';

/// Keeps everything in memory, mirroring the Supabase functions' behaviour.
/// For tests and for running the server without a database.
class InMemoryRoomRepository implements RoomRepository {
  final _rooms = <String, Room>{};
  final _players = <String, List<RoomPlayer>>{};
  final _games = <String, SavedGame>{};

  /// Last update saved per room, so tests can check what clients would see.
  final lastUpdates = <String, GameUpdate>{};

  var _nextId = 0;

  @override
  Future<String> createRoom({
    required String hostId,
    required String displayName,
    required String code,
  }) async {
    if (_rooms.values.any((r) => r.code == code)) throw const RoomCodeTaken();
    final id = 'room-${_nextId++}';
    _rooms[id] = Room(
      id: id,
      code: code,
      hostId: hostId,
      status: RoomStatus.lobby,
    );
    _players[id] = [
      RoomPlayer(userId: hostId, displayName: displayName, seat: 0),
    ];
    return id;
  }

  @override
  Future<String> joinRoom({
    required String code,
    required String userId,
    required String displayName,
  }) async {
    final room = _rooms.values.where((r) => r.code == code).firstOrNull;
    if (room == null) throw const AppException.notFound('Room not found');
    final players = _players[room.id]!;
    if (players.any((p) => p.userId == userId)) return room.id;
    if (room.status != RoomStatus.lobby) {
      throw const AppException.conflict('The game has already started');
    }
    if (players.length >= 6) {
      throw const AppException.conflict('The room is full');
    }
    players.add(
      RoomPlayer(
        userId: userId,
        displayName: displayName,
        seat: players.length,
      ),
    );
    return room.id;
  }

  @override
  Future<Room?> findRoom(String roomId) async => _rooms[roomId];

  @override
  Future<List<RoomPlayer>> players(String roomId) async => [
    ...?_players[roomId],
  ];

  @override
  Future<SavedGame?> loadGame(String roomId) async => _games[roomId];

  @override
  Future<bool> saveGame(GameUpdate update) async {
    final current = _games[update.roomId];
    if (current?.revision != update.expectedRevision) return false;
    _games[update.roomId] = SavedGame(
      state: update.state,
      revision: update.revision,
      deadlineAt: update.deadlineAt,
    );
    final room = _rooms[update.roomId]!;
    _rooms[update.roomId] = Room(
      id: room.id,
      code: room.code,
      hostId: room.hostId,
      status: update.status,
    );
    lastUpdates[update.roomId] = update;
    return true;
  }

  @override
  Future<List<String>> roomsPastDeadline(DateTime now) async => [
    for (final MapEntry(:key, :value) in _games.entries)
      if (value.deadlineAt case final d? when d.isBefore(now)) key,
  ];
}
