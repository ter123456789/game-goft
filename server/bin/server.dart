import 'dart:async';
import 'dart:io';

import 'package:coup_server/coup_server.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:supabase/supabase.dart';

/// Composition root: reads the environment and wires the adapters together.
///
/// Required: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.
/// Optional: PORT (8080), TURN_TIMEOUT_SECONDS (30).
Future<void> main() async {
  final env = Platform.environment;
  final db = SupabaseClient(
    _required(env, 'SUPABASE_URL'),
    _required(env, 'SUPABASE_SERVICE_ROLE_KEY'),
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
  final service = GameService(
    SupabaseRoomRepository(db),
    turnTimeout: Duration(
      seconds: int.parse(env['TURN_TIMEOUT_SECONDS'] ?? '30'),
    ),
  );

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(buildApi(service, SupabaseTokenVerifier(db)));
  final server = await shelf_io.serve(
    handler,
    InternetAddress.anyIPv4,
    int.parse(env['PORT'] ?? '8080'),
  );
  stdout.writeln('Coup server listening on port ${server.port}');

  _sweepTimeouts(service);
}

/// Moves for players who ran out of time. Safe with several server
/// instances: saves are guarded by the game's revision.
void _sweepTimeouts(GameService service) {
  var running = false;
  Timer.periodic(const Duration(seconds: 2), (_) async {
    if (running) return;
    running = true;
    try {
      await service.expireOverdue();
    } catch (e, stack) {
      stderr.writeln('Timeout sweep failed: $e\n$stack');
    } finally {
      running = false;
    }
  });
}

String _required(Map<String, String> env, String name) =>
    env[name] ?? (throw StateError('Set the $name environment variable'));
