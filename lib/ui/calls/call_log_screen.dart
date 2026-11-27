import 'package:flutter/material.dart';

/// Placeholder tab for the phone call log. Intentionally empty for now.
class CallLogScreen extends StatelessWidget {
  const CallLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.phone_in_talk_outlined, size: 48, color: scheme.outline),
            const SizedBox(height: 12),
            const Text('Belum ada log panggilan'),
          ],
        ),
      ),
    );
  }
}
