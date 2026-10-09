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
///
/// Values come from the environment, falling back to a `.env` file in the
/// working directory for local runs.
Future<void> main() async {
  final env = {..._readDotEnv(File('.env')), ...Platform.environment};
  final supabaseUrl = _required(env, 'SUPABASE_URL');
  final serviceKey = _required(env, 'SUPABASE_SERVICE_ROLE_KEY');
  if (serviceKey.startsWith('sb_publishable_')) {
    throw StateError(
      'SUPABASE_SERVICE_ROLE_KEY is the publishable key. Use the secret key '
      '(sb_secret_...) from Project Settings > API Keys.',
    );
  }
  final db = SupabaseClient(
    supabaseUrl,
    serviceKey,
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
  stdout
    ..writeln('Coup server listening on port ${server.port}')
    ..writeln('Using Supabase at $supabaseUrl');

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
    } catch (e) {
      // One line: this repeats every 2 seconds while the problem lasts.
      stderr.writeln('Timeout sweep failed: ${'$e'.split('\n').first}');
    } finally {
      running = false;
    }
  });
}

/// Parses `KEY=value` lines, skipping blanks and `#` comments.
Map<String, String> _readDotEnv(File file) {
  if (!file.existsSync()) return const {};
  return {
    for (final line in file.readAsLinesSync())
      if (line.trim() case final l when l.isNotEmpty && !l.startsWith('#'))
        if (l.indexOf('=') case final i when i > 0)
          l.substring(0, i).trim(): _unquote(l.substring(i + 1).trim()),
  };
}

String _unquote(String value) =>
    value.length >= 2 &&
        (value.startsWith('"') && value.endsWith('"') ||
            value.startsWith("'") && value.endsWith("'"))
    ? value.substring(1, value.length - 1)
    : value;

String _required(Map<String, String> env, String name) => switch (env[name]) {
  final String value when value.isNotEmpty => value,
  _ => throw StateError('Set $name in server/.env or the environment'),
};
