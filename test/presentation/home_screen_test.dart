import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_goft/presentation/app_services.dart';
import 'package:game_goft/presentation/home_screen.dart';

import '../fakes.dart';

class SleepyApi extends FakeApi {
  var pings = 0;
  bool answer = false;

  @override
  Future<bool> wakeUp() async {
    pings++;
    return answer;
  }
}

void main() {
  testWidgets('wakes the server on open and offers a retry', (tester) async {
    final api = SleepyApi();
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          services: AppServices(api: api, feed: FakeFeed('a'), myId: 'a'),
        ),
      ),
    );
    await tester.pump();
    expect(api.pings, 1);
    expect(find.text('ติดต่อ server ไม่ได้'), findsOneWidget);

    api.answer = true;
    await tester.tap(find.text('ลองใหม่'));
    await tester.pump();
    expect(api.pings, 2);
    expect(find.text('ติดต่อ server ไม่ได้'), findsNothing);

    // Keeps pinging while the app is open.
    await tester.pump(const Duration(minutes: 10));
    expect(api.pings, 3);
  });
}
