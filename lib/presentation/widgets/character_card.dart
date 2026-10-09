import 'package:coup_domain/coup_domain.dart';
import 'package:flutter/material.dart';

import '../texts.dart';

/// A face-up card. Revealed (lost) cards are faded and crossed out.
class CharacterCard extends StatelessWidget {
  const CharacterCard({
    super.key,
    required this.character,
    this.revealed = false,
    this.selected = false,
    this.small = false,
    this.onTap,
  });

  final Character character;
  final bool revealed;
  final bool selected;
  final bool small;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: small ? 52 : 104,
      height: small ? 72 : 148,
      padding: EdgeInsets.all(small ? 4 : 8),
      decoration: BoxDecoration(
        color: character.color,
        borderRadius: BorderRadius.circular(small ? 6 : 10),
        border: Border.all(
          color: selected ? Colors.amber : Colors.white24,
          width: selected ? 3 : 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FittedBox(
            child: Text(
              character.label,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: small ? 12 : 16,
                decoration: revealed ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (!small) ...[
            const SizedBox(height: 8),
            Text(
              character.ability,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ],
        ],
      ),
    );
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: revealed ? '${character.label} (เปิดแล้ว)' : character.label,
      child: Opacity(
        opacity: revealed ? 0.4 : 1,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: card,
        ),
      ),
    );
  }
}

/// A face-down card.
class CardBack extends StatelessWidget {
  const CardBack({super.key, this.small = false});

  final bool small;

  @override
  Widget build(BuildContext context) => Container(
    width: small ? 52 : 104,
    height: small ? 72 : 148,
    decoration: BoxDecoration(
      color: const Color(0xFF3A3150),
      borderRadius: BorderRadius.circular(small ? 6 : 10),
      border: Border.all(color: Colors.white24),
    ),
    child: const Center(child: Icon(Icons.help_outline, color: Colors.white24)),
  );
}
