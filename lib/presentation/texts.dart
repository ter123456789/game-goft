import 'package:coup_domain/coup_domain.dart';
import 'package:flutter/material.dart';

extension CharacterText on Character {
  String get label => switch (this) {
    Character.duke => 'Duke',
    Character.assassin => 'Assassin',
    Character.captain => 'Captain',
    Character.ambassador => 'Ambassador',
    Character.contessa => 'Contessa',
  };

  String get ability => switch (this) {
    Character.duke => 'เก็บภาษี +3\nบล็อกความช่วยเหลือต่างชาติ',
    Character.assassin => 'จ่าย 3 เพื่อลอบสังหาร',
    Character.captain => 'ขโมย 2 เหรียญ\nบล็อกการขโมย',
    Character.ambassador => 'แลกการ์ดกับกอง\nบล็อกการขโมย',
    Character.contessa => 'บล็อกการลอบสังหาร',
  };

  Color get color => switch (this) {
    Character.duke => const Color(0xFF7B2D8E),
    Character.assassin => const Color(0xFF2E2E2E),
    Character.captain => const Color(0xFF1F5FA8),
    Character.ambassador => const Color(0xFF2E7D4F),
    Character.contessa => const Color(0xFFB3261E),
  };
}

extension ActionText on ActionType {
  String get label => switch (this) {
    ActionType.income => 'รายได้ +1',
    ActionType.foreignAid => 'ช่วยเหลือต่างชาติ +2',
    ActionType.coup => 'รัฐประหาร (จ่าย 7)',
    ActionType.tax => 'เก็บภาษี +3',
    ActionType.assassinate => 'ลอบสังหาร (จ่าย 3)',
    ActionType.steal => 'ขโมย 2 เหรียญ',
    ActionType.exchange => 'แลกการ์ด',
  };
}

String describeAction(PendingAction action, String Function(String) name) {
  final target = action.targetId;
  final claim = action.type.claim;
  return [
    '${name(action.actorId)} ใช้ "${action.type.label}"',
    if (target != null) 'ใส่ ${name(target)}',
    if (claim != null) '(อ้างว่าเป็น ${claim.label})',
  ].join(' ');
}

/// One line for everyone at the table saying what is happening.
String describePhase(PublicGameView view, String Function(String) name) =>
    switch (view.phase) {
      AwaitingAction() => 'ตาของ ${name(view.currentPlayerId)}',
      AwaitingActionChallenge(:final action) =>
        '${describeAction(action, name)} มีใครจะจับโกหกไหม?',
      AwaitingBlock(:final action) when action.type.targeted =>
        '${describeAction(action, name)} ${name(action.targetId!)} จะบล็อกไหม?',
      AwaitingBlock(:final action) =>
        '${describeAction(action, name)} มีใครจะบล็อกด้วย Duke ไหม?',
      AwaitingBlockChallenge(:final block) =>
        '${name(block.blockerId)} บล็อกด้วย ${block.character.label} '
            'มีใครจะจับโกหกไหม?',
      AwaitingInfluenceLoss(:final playerId) =>
        '${name(playerId)} ต้องเปิดการ์ดทิ้ง 1 ใบ',
      AwaitingExchange(:final action) =>
        '${name(action.actorId)} กำลังเลือกการ์ดที่จะเก็บ',
      GameOver(:final winnerId) => '${name(winnerId)} ชนะ!',
    };
