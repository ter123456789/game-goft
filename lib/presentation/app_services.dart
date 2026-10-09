import '../application/game_api.dart';
import '../application/game_feed.dart';

/// The adapters the screens need, built once in main.dart.
class AppServices {
  const AppServices({
    required this.api,
    required this.feed,
    required this.myId,
  });

  final GameApi api;
  final GameFeed feed;

  /// The signed-in user's id, which is also their player id.
  final String myId;
}
