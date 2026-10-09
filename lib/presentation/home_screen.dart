import 'dart:async';

import 'package:flutter/material.dart';

import '../application/game_api.dart';
import 'app_services.dart';
import 'lobby_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  var _busy = false;

  /// null while checking.
  bool? _serverReady;

  /// Pings now and then so a free host doesn't put the server to sleep
  /// mid-game. This screen stays mounted under the lobby and the table.
  late final Timer _keepAwake;

  @override
  void initState() {
    super.initState();
    _wakeServer();
    _keepAwake = Timer.periodic(
      const Duration(minutes: 10),
      (_) => _wakeServer(),
    );
  }

  Future<void> _wakeServer() async {
    final ready = await widget.services.api.wakeUp();
    if (mounted) setState(() => _serverReady = ready);
  }

  @override
  void dispose() {
    _keepAwake.cancel();
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _enter(Future<String> Function(String name) request) async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _show('ใส่ชื่อก่อนนะ');
      return;
    }
    setState(() => _busy = true);
    try {
      final roomId = await request(name);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              LobbyScreen(services: widget.services, roomId: roomId),
        ),
      );
    } on GameApiException catch (e) {
      _show(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final api = widget.services.api;
    return Scaffold(
      appBar: AppBar(title: const Text('Coup')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ServerStatus(
            ready: _serverReady,
            onRetry: () {
              setState(() => _serverReady = null);
              _wakeServer();
            },
          ),
          TextField(
            controller: _name,
            maxLength: 32,
            decoration: const InputDecoration(labelText: 'ชื่อของคุณ'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy
                ? null
                : () => _enter(
                    (name) async => (await api.createRoom(name)).roomId,
                  ),
            child: const Text('สร้างห้องใหม่'),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('หรือ'),
                ),
                Expanded(child: Divider()),
              ],
            ),
          ),
          TextField(
            controller: _code,
            maxLength: 6,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'รหัสห้อง'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () => _enter((name) => api.joinRoom(_code.text, name)),
            child: const Text('เข้าร่วมห้อง'),
          ),
        ],
      ),
    );
  }
}

class _ServerStatus extends StatelessWidget {
  const _ServerStatus({required this.ready, required this.onRetry});

  final bool? ready;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => switch (ready) {
    true => const SizedBox.shrink(),
    null => const Padding(
      padding: EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('กำลังเชื่อมต่อ server… (ครั้งแรกอาจใช้เวลาถึง 1 นาที)'),
          SizedBox(height: 8),
          LinearProgressIndicator(),
        ],
      ),
    ),
    false => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          const Expanded(child: Text('ติดต่อ server ไม่ได้')),
          TextButton(onPressed: onRetry, child: const Text('ลองใหม่')),
        ],
      ),
    ),
  };
}
