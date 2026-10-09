import 'dart:math';

import 'package:coup_domain/coup_domain.dart';

import 'app_exception.dart';
import 'room_repository.dart';

/// The server's use cases: rooms, starting games, moves and timeouts.
class GameService {
  GameService(
    this._rooms, {
    this.turnTimeout = const Duration(seconds: 30),
    DateTime Function()? now,
    Random? random,
  }) : _now = now ?? DateTime.now,
       _random = random ?? Random.secure();

  final RoomRepository _rooms;
  final DateTime Function() _now;
  final Random _random;

  /// How long the players in `waitingFor` have before [expireOverdue] moves
  /// for them. Restarts on every phase change.
  final Duration turnTimeout;

  /// No 0/O or 1/I, so codes are easy to read out loud.
  static const _codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const _saveAttempts = 3;

  Future<({String roomId, String code})> createRoom(
    String userId,
    String displayName,
  ) async {
    final name = _checkName(displayName);
    for (var attempt = 0; attempt < 5; attempt++) {
      final code = _newCode();
      try {
        final roomId = await _rooms.createRoom(
          hostId: userId,
          displayName: name,
          code: code,
        );
        return (roomId: roomId, code: code);
      } on RoomCodeTaken {
        continue;
      }
    }
    throw StateError('Could not find a free room code');
  }

  Future<String> joinRoom(String userId, String code, String displayName) =>
      _rooms.joinRoom(
        code: code.trim().toUpperCase(),
        userId: userId,
        displayName: _checkName(displayName),
      );

  Future<void> startGame(String userId, String roomId) async {
    final room = await _rooms.findRoom(roomId);
    if (room == null) throw const AppException.notFound('Room not found');
    if (room.hostId != userId) {
      throw const AppException.forbidden('Only the host can start the game');
    }
    if (room.status != RoomStatus.lobby) {
      throw const AppException.conflict('The game has already started');
    }
    final players = await _rooms.players(roomId);
    final game = CoupGame.start([
      for (final p in players) p.userId,
    ], random: _random);
    if (!await _rooms.saveGame(_update(roomId, null, game))) {
      throw const AppException.conflict('The game has already started');
    }
  }

  /// Applies [command] for [userId]. Throws [GameRuleException] for illegal
  /// moves. Retries if another move was saved at the same time, checking the
  /// command again against the newer state.
  Future<void> submit(String userId, String roomId, GameCommand command) async {
    for (var attempt = 0; attempt < _saveAttempts; attempt++) {
      final saved = await _rooms.loadGame(roomId);
      if (saved == null) throw const AppException.notFound('No game here');
      final game = CoupGame.fromJson(saved.state, random: _random);
      if (!game.players.any((p) => p.id == userId)) {
        throw const AppException.forbidden('You are not in this game');
      }
      command.applyTo(game, userId);
      if (await _rooms.saveGame(_update(roomId, saved.revision, game))) return;
    }
    throw const AppException.conflict('The game changed; please try again');
  }

  /// Makes the default move in every game whose deadline has passed.
  /// Call it every few seconds. Returns how many games moved.
  Future<int> expireOverdue() async {
    var moved = 0;
    for (final roomId in await _rooms.roomsPastDeadline(_now())) {
      final saved = await _rooms.loadGame(roomId);
      // Someone may have moved since the query and pushed the deadline back.
      final deadline = saved?.deadlineAt;
      if (saved == null || deadline == null || deadline.isAfter(_now())) {
        continue;
      }
      final game = CoupGame.fromJson(saved.state, random: _random);
      if (game.phase is GameOver) continue;
      game.timeOut();
      // If this loses a race with a real move, the next sweep sees the new
      // deadline instead.
      if (await _rooms.saveGame(_update(roomId, saved.revision, game))) {
        moved++;
      }
    }
    return moved;
  }

  GameUpdate _update(String roomId, int? expectedRevision, CoupGame game) {
    final over = game.phase is GameOver;
    return GameUpdate(
      roomId: roomId,
      expectedRevision: expectedRevision,
      state: game.toJson(),
      revision: game.revision,
      deadlineAt: over ? null : _now().add(turnTimeout),
      publicView: game.publicView().toJson(),
      hands: {
        for (final p in game.players) p.id: game.privateView(p.id).toJson(),
      },
      status: over ? RoomStatus.finished : RoomStatus.playing,
    );
  }

  String _newCode() => String.fromCharCodes([
    for (var i = 0; i < 6; i++)
      _codeAlphabet.codeUnitAt(_random.nextInt(_codeAlphabet.length)),
  ]);

  static String _checkName(String displayName) {
    final name = displayName.trim();
    if (name.isEmpty || name.length > 32) {
      throw const FormatException('displayName must be 1 to 32 characters');
    }
    return name;
  }
}
