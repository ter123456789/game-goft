import 'package:coup_domain/coup_domain.dart';

enum RoomStatus { lobby, playing, finished }

class RoomInfo {
  const RoomInfo({
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

class Seat {
  const Seat({
    required this.userId,
    required this.displayName,
    required this.seat,
  });

  final String userId;
  final String displayName;
  final int seat;
}

class PublicSnapshot {
  const PublicSnapshot(this.view, this.deadlineAt);

  final PublicGameView view;

  /// When the server will move for the players in `view.waitingFor`.
  final DateTime? deadlineAt;
}

/// Live, read-only data about a room. Each stream emits the current value
/// first and then every change.
abstract interface class GameFeed {
  Stream<RoomInfo?> watchRoom(String roomId);

  /// Ordered by seat, which is also the turn order.
  Stream<List<Seat>> watchSeats(String roomId);

  Stream<PublicSnapshot?> watchPublicState(String roomId);

  /// The signed-in player's own hand.
  Stream<PrivateView?> watchMyHand(String roomId);
}
