import 'dart:async';

import 'package:coup_domain/coup_domain.dart';
import 'package:flutter/foundation.dart';

import 'game_api.dart';
import 'game_feed.dart';
import 'turn_prompt.dart';

/// State of the game table for the signed-in player.
class TableController extends ChangeNotifier {
  TableController({
    required GameApi api,
    required GameFeed feed,
    required this.roomId,
    required this.myId,
  }) : _api = api {
    _subscriptions = [
      feed.watchSeats(roomId).listen((seats) {
        names = {for (final s in seats) s.userId: s.displayName};
        notifyListeners();
      }, onError: _onError),
      feed.watchPublicState(roomId).listen((snapshot) {
        this.snapshot = snapshot;
        notifyListeners();
      }, onError: _onError),
      feed.watchMyHand(roomId).listen((hand) {
        _hand = hand;
        notifyListeners();
      }, onError: _onError),
    ];
  }

  final GameApi _api;
  final String roomId;
  final String myId;
  late final List<StreamSubscription<Object?>> _subscriptions;

  Map<String, String> names = const {};
  PublicSnapshot? snapshot;
  PrivateView? _hand;
  bool sending = false;
  String? error;

  PublicGameView? get view => snapshot?.view;

  /// My hand as last received, possibly a revision behind; for display.
  PrivateView? get latestHand => _hand;

  /// My hand, but only once it has caught up with the public state; the two
  /// rows arrive as separate realtime events.
  PrivateView? get hand {
    final hand = _hand;
    return hand != null && hand.revision == view?.revision ? hand : null;
  }

  TurnPrompt? get prompt {
    final view = this.view;
    return view == null ? null : promptFor(myId, view, hand);
  }

  String nameOf(String playerId) => names[playerId] ?? '…';

  Future<void> send(GameCommand command) async {
    if (sending) return;
    sending = true;
    error = null;
    notifyListeners();
    try {
      await _api.send(roomId, command);
    } on GameApiException catch (e) {
      error = e.message;
    } finally {
      sending = false;
      notifyListeners();
    }
  }

  void clearError() {
    error = null;
    notifyListeners();
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
