import 'dart:async';

import 'package:coup_domain/coup_domain.dart';
import 'package:game_goft/application/game_api.dart';
import 'package:game_goft/application/game_feed.dart';

class FakeApi implements GameApi {
  final sent = <GameCommand>[];

  /// Thrown by the next [send], then cleared.
  GameApiException? nextError;

  @override
  Future<void> send(String roomId, GameCommand command) async {
    final error = nextError;
    nextError = null;
    if (error != null) throw error;
    sent.add(command);
  }

  @override
  Future<bool> wakeUp() async => true;

  @override
  Future<({String roomId, String code})> createRoom(String displayName) async =>
      (roomId: 'room', code: 'ABCDEF');

  @override
  Future<String> joinRoom(String code, String displayName) async => 'room';

  @override
  Future<void> startGame(String roomId) async {}
}

/// Publishes views of a real [CoupGame] as if they came from Supabase.
class FakeFeed implements GameFeed {
  FakeFeed(this.myId);

  final String myId;
  final _room = StreamController<RoomInfo?>.broadcast();
  final _seats = StreamController<List<Seat>>.broadcast();
  final _public = StreamController<PublicSnapshot?>.broadcast();
  final _hand = StreamController<PrivateView?>.broadcast();

  void pushSeats(Map<String, String> names) => _seats.add([
    for (final (i, MapEntry(:key, :value)) in names.entries.indexed)
      Seat(userId: key, displayName: value, seat: i),
  ]);

  void pushGame(CoupGame game, {DateTime? deadline}) {
    _public.add(PublicSnapshot(game.publicView(), deadline));
    _hand.add(game.privateView(myId));
  }

  void pushRoom(RoomInfo room) => _room.add(room);

  @override
  Stream<RoomInfo?> watchRoom(String roomId) => _room.stream;

  @override
  Stream<List<Seat>> watchSeats(String roomId) => _seats.stream;

  @override
  Stream<PublicSnapshot?> watchPublicState(String roomId) => _public.stream;

  @override
  Stream<PrivateView?> watchMyHand(String roomId) => _hand.stream;
}
