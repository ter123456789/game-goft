import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'data/http_game_api.dart';
import 'data/supabase_game_feed.dart';
import 'presentation/app_services.dart';
import 'presentation/coup_app.dart';

/// Composition root: signs in and wires the adapters into the app.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (AppConfig.missing.isNotEmpty) {
    return runApp(
      StartupErrorApp(
        message:
            'ยังไม่ได้ตั้งค่า: ${AppConfig.missing.join(', ')}\n\n'
            'รันด้วย flutter run --dart-define-from-file=config.json\n'
            '(ดู config.example.json)',
      ),
    );
  }

  try {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseKey,
    );
    final client = Supabase.instance.client;
    final auth = client.auth;
    // Anonymous accounts persist on the device, so the player keeps the
    // same id (and their seat) across restarts.
    if (auth.currentUser == null) await auth.signInAnonymously();
    final myId = auth.currentUser!.id;

    var serverUrl = AppConfig.serverUrl;
    if (!serverUrl.endsWith('/')) serverUrl += '/';

    runApp(
      CoupApp(
        services: AppServices(
          api: HttpGameApi(
            baseUrl: Uri.parse(serverUrl),
            accessToken: () => auth.currentSession?.accessToken,
          ),
          feed: SupabaseGameFeed(client, myId),
          myId: myId,
        ),
      ),
    );
  } on AuthException catch (e) {
    runApp(
      StartupErrorApp(
        message:
            'เข้าสู่ระบบไม่ได้: ${e.message}\n\n'
            'เปิด Anonymous sign-ins ใน Supabase แล้วหรือยัง? '
            '(Authentication → Sign In / Providers)',
      ),
    );
  }
}
