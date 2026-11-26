import 'package:flutter/material.dart';

import 'ui/auth/auth_gate.dart';
import 'ui/theme.dart';

class SekitarApp extends StatelessWidget {
  const SekitarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sekitar',
      debugShowCheckedModeBanner: false,
      theme: buildSekitarTheme(),
      home: const AuthGate(),
    );
  }
}
