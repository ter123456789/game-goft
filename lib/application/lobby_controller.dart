import 'dart:async';

import 'package:flutter/foundation.dart';

import 'game_api.dart';
import 'game_feed.dart';

class LobbyController extends ChangeNotifier {
  LobbyController({
    required GameApi api,
    required GameFeed feed,
    required this.roomId,
    required this.myId,
  }) : _api = api {
    _subscriptions = [
      feed.watchRoom(roomId).listen((room) {
        this.room = room;
        notifyListeners();
      }, onError: _onError),
      feed.watchSeats(roomId).listen((seats) {
        this.seats = seats;
        notifyListeners();
      }, onError: _onError),
    ];
  }

  final GameApi _api;
  final String roomId;
  final String myId;
  late final List<StreamSubscription<Object?>> _subscriptions;

  RoomInfo? room;
  List<Seat> seats = const [];
  bool starting = false;
  String? error;

  bool get isHost => room?.hostId == myId;
  bool get canStart => isHost && seats.length >= 2 && !starting;

  Future<void> start() async {
    starting = true;
    error = null;
    notifyListeners();
    try {
      await _api.startGame(roomId);
    } on GameApiException catch (e) {
      error = e.message;
    } finally {
      starting = false;
      notifyListeners();
    }
  }

  void _onError(Object e) {
    error = 'เชื่อมต่อไม่ได้: $e';
    notifyListeners();
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }
}
