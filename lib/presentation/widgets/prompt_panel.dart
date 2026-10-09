import 'package:coup_domain/coup_domain.dart';
import 'package:flutter/material.dart';

import '../../application/table_controller.dart';
import '../../application/turn_prompt.dart';
import '../texts.dart';
import 'character_card.dart';

/// The buttons for whatever the signed-in player is being asked to do.
class PromptPanel extends StatelessWidget {
  const PromptPanel({super.key, required this.controller});

  final TableController controller;

  @override
  Widget build(BuildContext context) {
    final prompt = controller.prompt;
    final send = controller.sending ? null : controller.send;
    final name = controller.nameOf;

    final Widget child = switch (prompt) {
      null => const _Status('กำลังโหลด…'),
      WaitForOthers(:final playerIds) when playerIds.isEmpty => const _Status(
        'กำลังซิงค์…',
      ),
      WaitForOthers(:final playerIds) => _Status(
        'รอ ${playerIds.map(name).join(', ')}',
      ),
      GameFinished(:final winnerId) => Column(
        children: [
          Text(
            winnerId == controller.myId ? 'คุณชนะ!' : '${name(winnerId)} ชนะ',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
            child: const Text('กลับหน้าแรก'),
          ),
        ],
      ),
      final ChooseAction choose => _ActionChooser(
        prompt: choose,
        send: send,
        name: name,
      ),
      ChallengeAction(:final action) => _Choice(
        title: '${describeAction(action, name)}\nจะจับโกหกไหม?',
        buttons: [
          _Option('จับโกหก!', send, const ChallengeCommand(), primary: true),
          _Option('ผ่าน', send, const PassCommand()),
        ],
      ),
      final BlockOrPass block => _Choice(
        title: '${describeAction(block.action, name)}\nจะบล็อกไหม?',
        buttons: [
          for (final c in block.blockers)
            _Option(
              'บล็อกด้วย ${c.label}${block.hand.contains(c) ? ' ✓' : ''}',
              send,
              BlockCommand(c),
              primary: true,
            ),
          _Option('ไม่บล็อก', send, const PassCommand()),
        ],
      ),
      ChallengeBlock(:final block) => _Choice(
        title:
            '${name(block.blockerId)} บล็อกด้วย ${block.character.label}\n'
            'จะจับโกหกไหม?',
        buttons: [
          _Option('จับโกหก!', send, const ChallengeCommand(), primary: true),
          _Option('ผ่าน', send, const PassCommand()),
        ],
      ),
      ChooseCardToLose(:final hand) => Column(
        children: [
          const Text('เลือกการ์ดที่จะเปิดทิ้ง 1 ใบ'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final c in hand)
                CharacterCard(
                  character: c,
                  onTap: send == null
                      ? null
                      : () => send(LoseInfluenceCommand(c)),
                ),
            ],
          ),
        ],
      ),
      ChooseCardsToKeep(:final options, :final keepCount) => _ExchangePicker(
        // A new set of options starts a fresh selection.
        key: ValueKey(options),
        options: options,
        keepCount: keepCount,
        send: send,
      ),
    };

    return Padding(padding: const EdgeInsets.all(12), child: child);
  }
}

typedef _Send = Future<void> Function(GameCommand)?;

class _Status extends StatelessWidget {
  const _Status(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.center,
    style: Theme.of(context).textTheme.bodyLarge,
  );
}

class _Option {
  const _Option(this.label, this.send, this.command, {this.primary = false});

  final String label;
  final _Send send;
  final GameCommand command;
  final bool primary;
}

class _Choice extends StatelessWidget {
  const _Choice({required this.title, required this.buttons});

  final String title;
  final List<_Option> buttons;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(title, textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          for (final b in buttons)
            if (b.primary)
              FilledButton(
                onPressed: b.send == null ? null : () => b.send!(b.command),
                child: Text(b.label),
              )
            else
              OutlinedButton(
                onPressed: b.send == null ? null : () => b.send!(b.command),
                child: Text(b.label),
              ),
        ],
      ),
    ],
  );
}

class _ActionChooser extends StatelessWidget {
  const _ActionChooser({
    required this.prompt,
    required this.send,
    required this.name,
  });

  final ChooseAction prompt;
  final _Send send;
  final String Function(String) name;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        prompt.mustCoup ? 'มี 10 เหรียญขึ้นไป ต้องรัฐประหาร' : 'ตาของคุณ',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          for (final type in ActionType.values) _actionButton(context, type),
        ],
      ),
    ],
  );

  Widget _actionButton(BuildContext context, ActionType type) {
    final claim = type.claim;
    final label = claim == null
        ? type.label
        // ✓ = you really hold it; otherwise you would be bluffing.
        : '${type.label} · ${claim.label}${prompt.hand.contains(claim) ? ' ✓' : ''}';
    final enabled = send != null && prompt.isAllowed(type);
    return OutlinedButton(
      onPressed: !enabled
          ? null
          : () async {
              if (!type.targeted) return send!(DeclareActionCommand(type));
              final target = await _pickTarget(context, type);
              if (target != null) {
                await send!(DeclareActionCommand(type, targetId: target));
              }
            },
      child: Text(label),
    );
  }

  Future<String?> _pickTarget(BuildContext context, ActionType type) =>
      showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(title: Text('${type.label} ใส่ใคร?')),
              for (final id in prompt.targets)
                ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(name(id)),
                  onTap: () => Navigator.of(context).pop(id),
                ),
            ],
          ),
        ),
      );
}

class _ExchangePicker extends StatefulWidget {
  const _ExchangePicker({
    super.key,
    required this.options,
    required this.keepCount,
    required this.send,
  });

  final List<Character> options;
  final int keepCount;
  final _Send send;

  @override
  State<_ExchangePicker> createState() => _ExchangePickerState();
}

class _ExchangePickerState extends State<_ExchangePicker> {
  // Indexes, because the options can hold two of the same character.
  final _selected = <int>{};

  @override
  Widget build(BuildContext context) {
    final ready = _selected.length == widget.keepCount && widget.send != null;
    return Column(
      children: [
        Text('เลือกการ์ดที่จะเก็บ ${widget.keepCount} ใบ'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final (i, c) in widget.options.indexed)
              CharacterCard(
                character: c,
                selected: _selected.contains(i),
                onTap: () => setState(() {
                  if (!_selected.remove(i) &&
                      _selected.length < widget.keepCount) {
                    _selected.add(i);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: !ready
              ? null
              : () => widget.send!(
                  ExchangeCommand([
                    for (final i in _selected) widget.options[i],
                  ]),
                ),
          child: const Text('ยืนยัน'),
        ),
      ],
    );
  }
}
