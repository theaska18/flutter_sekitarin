import 'package:flutter/material.dart';

import 'services/call_service.dart';
import 'ui/auth/auth_gate.dart';
import 'ui/theme.dart';

class SekitarApp extends StatelessWidget {
  const SekitarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sekitarin',
      navigatorKey: CallService.navigatorKey,
      scaffoldMessengerKey: CallService.messengerKey,
      debugShowCheckedModeBanner: false,
      theme: buildSekitarTheme(Brightness.light),
      darkTheme: buildSekitarTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const AuthGate(),
    );
  }
}
