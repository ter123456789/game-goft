import 'package:flutter/material.dart';

import 'app_services.dart';
import 'home_screen.dart';

ThemeData _theme() => ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.deepPurple,
    brightness: Brightness.dark,
  ),
);

class CoupApp extends StatelessWidget {
  const CoupApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Coup',
    theme: _theme(),
    home: HomeScreen(services: services),
  );
}

/// Shown instead of the game when the app cannot start.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Coup',
    theme: _theme(),
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SelectableText(message, textAlign: TextAlign.center),
        ),
      ),
    ),
  );
}
