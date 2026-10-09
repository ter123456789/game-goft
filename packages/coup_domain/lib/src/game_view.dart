part of 'coup_game.dart';

/// A player as everyone else sees them: hidden cards are only counted.
class PublicPlayerView {
  const PublicPlayerView({
    required this.id,
    required this.coins,
    required this.hiddenCount,
    required this.revealed,
  });

  final String id;
  final int coins;
  final int hiddenCount;
  final List<Character> revealed;

  bool get isAlive => hiddenCount > 0;
}

/// The part of the game that is safe to send to every player in the room.
class PublicGameView {
  const PublicGameView({
    required this.revision,
    required this.currentPlayerId,
    required this.deckSize,
    required this.players,
    required this.phase,
    required this.waitingFor,
  });

  factory PublicGameView.fromJson(Map<String, Object?> json) {
    if (json case {
      'revision': int revision,
      'currentPlayerId': String currentPlayerId,
      'deckSize': int deckSize,
      'players': List players,
      'phase': final phase,
      'waitingFor': List waitingFor,
    }) {
      return PublicGameView(
        revision: revision,
        currentPlayerId: currentPlayerId,
        deckSize: deckSize,
        players: [for (final p in players) _publicPlayerFromJson(p)],
        phase: _phaseFromJson(phase),
        waitingFor: _ids(waitingFor),
      );
    }
    throw _invalid('public view', json);
  }

  final int revision;
  final String currentPlayerId;
  final int deckSize;
  final List<PublicPlayerView> players;

  /// The current phase. [AwaitingExchange.options] is always empty here;
  /// only the exchanging player gets them, in [PrivateView.exchangeOptions].
  final Phase phase;

  final Set<String> waitingFor;

  Map<String, Object?> toJson() => {
    'revision': revision,
    'currentPlayerId': currentPlayerId,
    'deckSize': deckSize,
    'players': [
      for (final p in players)
        {
          'id': p.id,
          'coins': p.coins,
          'hiddenCount': p.hiddenCount,
          'revealed': [for (final c in p.revealed) c.name],
        },
    ],
    'phase': _phaseToJson(phase),
    'waitingFor': waitingFor.toList(),
  };
}

/// What only [playerId] may see.
class PrivateView {
  const PrivateView({
    required this.playerId,
    required this.revision,
    required this.hand,
    this.exchangeOptions,
  });

  factory PrivateView.fromJson(Map<String, Object?> json) {
    if (json case {
      'playerId': String playerId,
      'revision': int revision,
      'hand': List hand,
    }) {
      return PrivateView(
        playerId: playerId,
        revision: revision,
        hand: _characters(hand),
        exchangeOptions: switch (json['exchangeOptions']) {
          final List options => _characters(options),
          null => null,
          final other => throw _invalid('exchangeOptions', other),
        },
      );
    }
    throw _invalid('private view', json);
  }

  final String playerId;
  final int revision;

  /// The player's hidden cards.
  final List<Character> hand;

  /// The cards to choose from while this player is exchanging, else null.
  final List<Character>? exchangeOptions;

  Map<String, Object?> toJson() => {
    'playerId': playerId,
    'revision': revision,
    'hand': [for (final c in hand) c.name],
    if (exchangeOptions case final options?)
      'exchangeOptions': [for (final c in options) c.name],
  };
}

PublicGameView _publicView(CoupGame game) => PublicGameView(
  revision: game._revision,
  currentPlayerId: game.currentPlayer.id,
  deckSize: game._deck.length,
  players: [
    for (final p in game._players)
      PublicPlayerView(
        id: p.id,
        coins: p.coins,
        hiddenCount: p.hiddenCharacters.length,
        revealed: [
          for (final i in p._influences)
            if (i.revealed) i.character,
        ],
      ),
  ],
  phase: switch (game._phase) {
    AwaitingExchange(:final action, :final keepCount) => AwaitingExchange(
      action,
      const [],
      keepCount,
    ),
    final phase => phase,
  },
  waitingFor: game.waitingFor,
);

PrivateView _privateView(CoupGame game, String playerId) => PrivateView(
  playerId: playerId,
  revision: game._revision,
  hand: game.player(playerId).hiddenCharacters,
  exchangeOptions: switch (game._phase) {
    AwaitingExchange(:final action, :final options)
        when action.actorId == playerId =>
      options,
    _ => null,
  },
);

PublicPlayerView _publicPlayerFromJson(Object? json) => switch (json) {
  {
    'id': String id,
    'coins': int coins,
    'hiddenCount': int hiddenCount,
    'revealed': List revealed,
  } =>
    PublicPlayerView(
      id: id,
      coins: coins,
      hiddenCount: hiddenCount,
      revealed: _characters(revealed),
    ),
  _ => throw _invalid('player view', json),
};

List<Character> _characters(List json) => [
  for (final c in json) _enum(Character.values, c),
];
