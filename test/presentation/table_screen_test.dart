import 'package:coup_domain/coup_domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_goft/application/game_api.dart';
import 'package:game_goft/presentation/app_services.dart';
import 'package:game_goft/presentation/table_screen.dart';
import 'package:game_goft/presentation/widgets/character_card.dart';

import '../fakes.dart';

const names = {'a': 'Ann', 'b': 'Bo', 'c': 'Cy'};

CoupGame newGame({List<int> coins = const [2, 2, 2]}) => CoupGame.fromPosition(
  players: [
    (id: 'a', hand: [Character.duke, Character.captain], coins: coins[0]),
    (id: 'b', hand: [Character.contessa, Character.duke], coins: coins[1]),
    (
      id: 'c',
      hand: [Character.assassin, Character.ambassador],
      coins: coins[2],
    ),
  ],
  deck: [Character.captain, Character.contessa],
);

/// A card the player can tap (not one shown just for information).
Finder tappableCard(Character character) => find.byWidgetPredicate(
  (w) => w is CharacterCard && w.character == character && w.onTap != null,
);

void main() {
  late FakeApi api;
  late FakeFeed feed;

  /// Shows the table as player [me] with [game] already on it.
  Future<void> showTable(WidgetTester tester, String me, CoupGame game) async {
    api = FakeApi();
    feed = FakeFeed(me);
    await tester.pumpWidget(
      MaterialApp(
        home: TableScreen(
          services: AppServices(api: api, feed: feed, myId: me),
          roomId: 'room',
        ),
      ),
    );
    feed
      ..pushSeats(names)
      ..pushGame(game);
    await tester.pump();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('shows opponents and who we are waiting for', (tester) async {
    await showTable(tester, 'b', newGame());
    expect(find.text('Ann'), findsOneWidget);
    expect(find.text('Cy'), findsOneWidget);
    expect(find.text('ตาของ Ann'), findsOneWidget);
    expect(find.text('รอ Ann'), findsOneWidget);
  });

  testWidgets('my turn: income sends a declareAction command', (tester) async {
    await showTable(tester, 'a', newGame());
    await tap(tester, find.text('รายได้ +1'));
    expect(api.sent.single.toJson(), {
      'type': 'declareAction',
      'action': 'income',
    });
  });

  testWidgets('a true claim is marked with ✓', (tester) async {
    await showTable(tester, 'a', newGame());
    expect(find.text('เก็บภาษี +3 · Duke ✓'), findsOneWidget);
    expect(find.text('แลกการ์ด · Ambassador'), findsOneWidget);
  });

  testWidgets('a targeted action asks for a target', (tester) async {
    await showTable(tester, 'a', newGame());
    await tap(tester, find.textContaining('ขโมย 2 เหรียญ'));
    expect(find.text('ขโมย 2 เหรียญ ใส่ใคร?'), findsOneWidget);
    await tap(tester, find.widgetWithText(ListTile, 'Cy'));
    expect(api.sent.single.toJson(), {
      'type': 'declareAction',
      'action': 'steal',
      'targetId': 'c',
    });
  });

  testWidgets('with 10 coins only coup is enabled', (tester) async {
    await showTable(tester, 'a', newGame(coins: [10, 2, 2]));
    expect(find.text('มี 10 เหรียญขึ้นไป ต้องรัฐประหาร'), findsOneWidget);
    final income = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'รายได้ +1'),
    );
    expect(income.onPressed, isNull);
  });

  testWidgets('someone else claims tax: I can challenge', (tester) async {
    await showTable(tester, 'b', newGame()..declareAction('a', ActionType.tax));
    expect(find.textContaining('อ้างว่าเป็น Duke'), findsWidgets);
    await tap(tester, find.text('จับโกหก!'));
    expect(api.sent.single, isA<ChallengeCommand>());
  });

  testWidgets('blocking a steal offers Captain and Ambassador', (tester) async {
    await showTable(
      tester,
      'b',
      newGame()
        ..declareAction('a', ActionType.steal, targetId: 'b')
        ..pass('b')
        ..pass('c'),
    );
    expect(find.text('บล็อกด้วย Captain'), findsOneWidget);
    await tap(tester, find.text('บล็อกด้วย Ambassador'));
    expect(api.sent.single.toJson(), {
      'type': 'block',
      'character': 'ambassador',
    });
  });

  testWidgets('choosing which card to lose', (tester) async {
    await showTable(
      tester,
      'c',
      newGame(coins: [7, 2, 2])
        ..declareAction('a', ActionType.coup, targetId: 'c'),
    );
    expect(find.text('เลือกการ์ดที่จะเปิดทิ้ง 1 ใบ'), findsOneWidget);
    await tap(tester, tappableCard(Character.ambassador));
    expect(api.sent.single.toJson(), {
      'type': 'loseInfluence',
      'character': 'ambassador',
    });
  });

  testWidgets('exchange: pick exactly 2 cards, then confirm', (tester) async {
    await showTable(
      tester,
      'a',
      newGame()
        ..declareAction('a', ActionType.exchange)
        ..pass('b')
        ..pass('c'),
    );
    final confirm = find.widgetWithText(FilledButton, 'ยืนยัน');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tap(tester, tappableCard(Character.contessa));
    await tap(tester, tappableCard(Character.duke));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);

    await tap(tester, confirm);
    expect(api.sent.single.toJson(), {
      'type': 'exchange',
      'keep': ['contessa', 'duke'],
    });
  });

  testWidgets('a refused move shows the server message', (tester) async {
    await showTable(tester, 'a', newGame());
    api.nextError = const GameApiException(422, 'Not your turn');
    await tap(tester, find.text('รายได้ +1'));
    expect(find.text('Not your turn'), findsOneWidget);
    expect(api.sent, isEmpty);
  });

  testWidgets('game over shows the winner', (tester) async {
    final game = CoupGame.fromPosition(
      players: [
        (id: 'a', hand: [Character.duke], coins: 7),
        (id: 'b', hand: [Character.captain], coins: 2),
      ],
      deck: [],
    )..declareAction('a', ActionType.coup, targetId: 'b');
    await showTable(tester, 'a', game);
    expect(find.text('คุณชนะ!'), findsOneWidget);
  });
}
