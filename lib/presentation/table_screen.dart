import 'dart:async';

import 'package:coup_domain/coup_domain.dart';
import 'package:flutter/material.dart';

import '../application/table_controller.dart';
import 'app_services.dart';
import 'texts.dart';
import 'widgets/character_card.dart';
import 'widgets/prompt_panel.dart';

class TableScreen extends StatefulWidget {
  const TableScreen({super.key, required this.services, required this.roomId});

  final AppServices services;
  final String roomId;

  @override
  State<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends State<TableScreen> {
  late final TableController _controller = TableController(
    api: widget.services.api,
    feed: widget.services.feed,
    roomId: widget.roomId,
    myId: widget.services.myId,
  )..addListener(_showErrors);

  void _showErrors() {
    final error = _controller.error;
    if (error == null || !mounted) return;
    _controller.clearError();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Coup')),
    body: ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final view = _controller.view;
        if (view == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final me = view.players.where((p) => p.id == _controller.myId);
        return SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    for (final p in view.players)
                      if (p.id != _controller.myId)
                        _PlayerTile(
                          player: p,
                          name: _controller.nameOf(p.id),
                          isTurn: p.id == view.currentPlayerId,
                          isWaitedOn: view.waitingFor.contains(p.id),
                        ),
                  ],
                ),
              ),
              _PhaseBanner(
                text: describePhase(view, _controller.nameOf),
                deadline: _controller.snapshot?.deadlineAt,
              ),
              if (me.isNotEmpty) _MyArea(controller: _controller, me: me.first),
              // Up to half the screen; scrolls when the exchange cards
              // don't fit.
              Flexible(
                child: SingleChildScrollView(
                  child: PromptPanel(controller: _controller),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _PlayerTile extends StatelessWidget {
  const _PlayerTile({
    required this.player,
    required this.name,
    required this.isTurn,
    required this.isWaitedOn,
  });

  final PublicPlayerView player;
  final String name;
  final bool isTurn;
  final bool isWaitedOn;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Opacity(
      opacity: player.isAlive ? 1 : 0.4,
      child: Card(
        shape: isTurn
            ? RoundedRectangleBorder(
                side: BorderSide(color: colors.primary, width: 2),
                borderRadius: BorderRadius.circular(12),
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (isWaitedOn) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.hourglass_top, size: 16),
                        ],
                      ],
                    ),
                    Text(player.isAlive ? '🪙 ${player.coins}' : 'ตกรอบแล้ว'),
                  ],
                ),
              ),
              for (var i = 0; i < player.hiddenCount; i++)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: CardBack(small: true),
                ),
              for (final c in player.revealed)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: CharacterCard(
                    character: c,
                    revealed: true,
                    small: true,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MyArea extends StatelessWidget {
  const _MyArea({required this.controller, required this.me});

  final TableController controller;
  final PublicPlayerView me;

  @override
  Widget build(BuildContext context) {
    // Show the last known hand even while it is syncing with the table.
    final hand = controller.latestHand?.hand ?? const <Character>[];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Text(
            'คุณ · 🪙 ${me.coins}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Spacer(),
          for (final c in hand)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: CharacterCard(character: c, small: true),
            ),
          for (final c in me.revealed)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: CharacterCard(character: c, revealed: true, small: true),
            ),
        ],
      ),
    );
  }
}

class _PhaseBanner extends StatelessWidget {
  const _PhaseBanner({required this.text, required this.deadline});

  final String text;
  final DateTime? deadline;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: Theme.of(context).colorScheme.secondaryContainer,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(
      children: [
        Expanded(child: Text(text)),
        if (deadline case final deadline?) _Countdown(deadline: deadline),
      ],
    ),
  );
}

class _Countdown extends StatefulWidget {
  const _Countdown({required this.deadline});

  final DateTime deadline;

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.deadline.difference(DateTime.now()).inSeconds;
    return Text('⏱ ${left.clamp(0, 999)} วิ');
  }
}
