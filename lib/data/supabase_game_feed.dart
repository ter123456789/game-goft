import 'package:coup_domain/coup_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/game_feed.dart';

/// Reads rooms and games through Supabase Realtime. RLS decides what this
/// user can see (supabase/migrations).
class SupabaseGameFeed implements GameFeed {
  SupabaseGameFeed(this._db, this._myId);

  final SupabaseClient _db;
  final String _myId;

  @override
  Stream<RoomInfo?> watchRoom(String roomId) => _db
      .from('rooms')
      .stream(primaryKey: ['id'])
      .eq('id', roomId)
      .map(
        (rows) => rows.isEmpty
            ? null
            : RoomInfo(
                id: rows.first['id'] as String,
                code: rows.first['code'] as String,
                hostId: rows.first['host_id'] as String,
                status: RoomStatus.values.byName(
                  rows.first['status'] as String,
                ),
              ),
      );

  @override
  Stream<List<Seat>> watchSeats(String roomId) => _db
      .from('room_players')
      .stream(primaryKey: ['room_id', 'user_id'])
      .eq('room_id', roomId)
      .order('seat', ascending: true)
      .map(
        (rows) => [
          for (final row in rows)
            Seat(
              userId: row['user_id'] as String,
              displayName: row['display_name'] as String,
              seat: row['seat'] as int,
            ),
        ],
      );

  @override
  Stream<PublicSnapshot?> watchPublicState(String roomId) => _db
      .from('game_public_state')
      .stream(primaryKey: ['room_id'])
      .eq('room_id', roomId)
      .map(
        (rows) => rows.isEmpty
            ? null
            : PublicSnapshot(
                PublicGameView.fromJson(
                  rows.first['view'] as Map<String, Object?>,
                ),
                switch (rows.first['deadline_at']) {
                  final String s => DateTime.parse(s),
                  _ => null,
                },
              ),
      );

  @override
  Stream<PrivateView?> watchMyHand(String roomId) => _db
      .from('player_hands')
      .stream(primaryKey: ['room_id', 'user_id'])
      .eq('room_id', roomId)
      .map((rows) {
        // RLS already limits this to my row; filter anyway.
        final mine = rows.where((r) => r['user_id'] == _myId).firstOrNull;
        return mine == null
            ? null
            : PrivateView.fromJson(mine['view'] as Map<String, Object?>);
      });
}
