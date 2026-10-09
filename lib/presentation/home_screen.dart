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

  @override
  void dispose() {
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
