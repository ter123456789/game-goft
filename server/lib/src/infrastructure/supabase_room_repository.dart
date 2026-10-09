import 'package:supabase/supabase.dart';

import '../application/app_exception.dart';
import '../application/room_repository.dart';

/// Stores rooms and games in Supabase through the functions and tables in
/// supabase/migrations. Needs a service-role client.
class SupabaseRoomRepository implements RoomRepository {
  SupabaseRoomRepository(this._db);

  final SupabaseClient _db;

  static const _uniqueViolation = '23505';
  static const _invalidText = '22P02';

  @override
  Future<String> createRoom({
    required String hostId,
    required String displayName,
    required String code,
  }) async {
    try {
      return await _db.rpc<String>(
        'create_room',
        params: {
          'p_host_id': hostId,
          'p_display_name': displayName,
          'p_code': code,
        },
      );
    } on PostgrestException catch (e) {
      if (e.code == _uniqueViolation) throw const RoomCodeTaken();
      rethrow;
    }
  }

  @override
  Future<String> joinRoom({
    required String code,
    required String userId,
    required String displayName,
  }) async {
    try {
      return await _db.rpc<String>(
        'join_room',
        params: {
          'p_code': code,
          'p_user_id': userId,
          'p_display_name': displayName,
        },
      );
    } on PostgrestException catch (e) {
      throw switch (e.message) {
        'room_not_found' => const AppException.notFound('Room not found'),
        'room_not_open' => const AppException.conflict(
          'The game has already started',
        ),
        'room_full' => const AppException.conflict('The room is full'),
        _ => e,
      };
    }
  }

  @override
  Future<Room?> findRoom(String roomId) => _nullIfBadId(() async {
    final row = await _db
        .from('rooms')
        .select('id, code, host_id, status')
        .eq('id', roomId)
        .maybeSingle();
    if (row == null) return null;
    return Room(
      id: row['id'] as String,
      code: row['code'] as String,
      hostId: row['host_id'] as String,
      status: RoomStatus.values.byName(row['status'] as String),
    );
  });

  @override
  Future<List<RoomPlayer>> players(String roomId) async {
    final rows = await _db
        .from('room_players')
        .select('user_id, display_name, seat')
        .eq('room_id', roomId)
        .order('seat');
    return [
      for (final row in rows)
        RoomPlayer(
          userId: row['user_id'] as String,
          displayName: row['display_name'] as String,
          seat: row['seat'] as int,
        ),
    ];
  }

  @override
  Future<SavedGame?> loadGame(String roomId) => _nullIfBadId(() async {
    final row = await _db
        .from('game_saves')
        .select('state, revision, deadline_at')
        .eq('room_id', roomId)
        .maybeSingle();
    if (row == null) return null;
    return SavedGame(
      state: row['state'] as Map<String, Object?>,
      revision: row['revision'] as int,
      deadlineAt: switch (row['deadline_at']) {
        final String s => DateTime.parse(s),
        _ => null,
      },
    );
  });

  @override
  Future<bool> saveGame(GameUpdate update) async => await _db.rpc<bool>(
    'save_game',
    params: {
      'p_room_id': update.roomId,
      'p_expected_revision': update.expectedRevision,
      'p_state': update.state,
      'p_revision': update.revision,
      'p_deadline_at': update.deadlineAt?.toUtc().toIso8601String(),
      'p_public_view': update.publicView,
      'p_hands': update.hands,
      'p_status': update.status.name,
    },
  );

  @override
  Future<List<String>> roomsPastDeadline(DateTime now) async {
    final rows = await _db
        .from('game_saves')
        .select('room_id')
        .lt('deadline_at', now.toUtc().toIso8601String());
    return [for (final row in rows) row['room_id'] as String];
  }

  /// A room id that is not a UUID is simply a room that does not exist.
  Future<T?> _nullIfBadId<T>(Future<T?> Function() query) async {
    try {
      return await query();
    } on PostgrestException catch (e) {
      if (e.code == _invalidText) return null;
      rethrow;
    }
  }
}
