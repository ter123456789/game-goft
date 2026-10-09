import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/game_feed.dart';
import '../application/lobby_controller.dart';
import 'app_services.dart';
import 'table_screen.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key, required this.services, required this.roomId});

  final AppServices services;
  final String roomId;

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  late final LobbyController _controller = LobbyController(
    api: widget.services.api,
    feed: widget.services.feed,
    roomId: widget.roomId,
    myId: widget.services.myId,
  )..addListener(_onChange);

  var _leftLobby = false;

  void _onChange() {
    if (!mounted) return;
    final error = _controller.error;
    if (error != null) {
      _controller.error = null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
    // Everyone moves to the table as soon as the host starts.
    final status = _controller.room?.status;
    if (status != null && status != RoomStatus.lobby && !_leftLobby) {
      _leftLobby = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              TableScreen(services: widget.services, roomId: widget.roomId),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ห้องรอ')),
    body: ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final room = _controller.room;
        if (room == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final textTheme = Theme.of(context).textTheme;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('รหัสห้อง', style: textTheme.labelLarge),
            Row(
              children: [
                SelectableText(
                  room.code,
                  style: textTheme.displaySmall?.copyWith(letterSpacing: 6),
                ),
                IconButton(
                  tooltip: 'คัดลอกรหัส',
                  icon: const Icon(Icons.copy),
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: room.code)),
                ),
              ],
            ),
            const Text('ส่งรหัสนี้ให้เพื่อนเพื่อเข้าห้อง (2–6 คน)'),
            const SizedBox(height: 16),
            Text(
              'ผู้เล่น (${_controller.seats.length}/6)',
              style: textTheme.titleMedium,
            ),
            for (final seat in _controller.seats)
              ListTile(
                leading: const Icon(Icons.person),
                title: Text(seat.displayName),
                trailing: seat.userId == room.hostId
                    ? const Chip(label: Text('Host'))
                    : null,
              ),
            const SizedBox(height: 16),
            if (_controller.isHost)
              FilledButton(
                onPressed: _controller.canStart ? _controller.start : null,
                child: Text(
                  _controller.seats.length < 2
                      ? 'รอเพื่อนอีกอย่างน้อย 1 คน'
                      : 'เริ่มเกม',
                ),
              )
            else
              const Text('รอ host เริ่มเกม…', textAlign: TextAlign.center),
          ],
        );
      },
    ),
  );
}
