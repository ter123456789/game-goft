/// Build-time settings. The defaults point at the project's Supabase, so
/// `flutter run` just works; override with
/// `flutter run --dart-define-from-file=config.json` (see config.example.json),
/// e.g. to set SERVER_URL for an emulator or phone.
abstract final class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://xeuispkthkkjepsuwxpo.supabase.co',
  );

  /// The publishable (or legacy anon) key. Safe to ship in the app; RLS
  /// protects the data. Never put the service role key here.
  static const supabaseKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: 'sb_publishable_p4kk9FT7j7ZnRhyDqxXTHQ_GDoTe6uU',
  );

  static const serverUrl = String.fromEnvironment(
    'SERVER_URL',
    defaultValue: 'http://localhost:8080/',
  );

  static List<String> get missing => [
    if (supabaseUrl.isEmpty) 'SUPABASE_URL',
    if (supabaseKey.isEmpty) 'SUPABASE_PUBLISHABLE_KEY',
  ];
}
