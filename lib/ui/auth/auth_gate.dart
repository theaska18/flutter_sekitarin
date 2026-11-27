import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_store.dart';
import '../home/home_shell.dart';
import 'login_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final auth = context.read<AuthStore>();
    if (!auth.signedIn && auth.hasStoredToken) {
      auth.retryBootstrap();
    } else if (auth.signedIn) {
      auth.reconnectRealtime();
      auth.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthStore>();
    if (auth.loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (auth.signedIn) return const HomeShell();
    if (auth.hasStoredToken) {
      return _ConnectionRetry(auth: auth);
    }
    return const LoginScreen();
  }
}

class _ConnectionRetry extends StatelessWidget {
  const _ConnectionRetry({required this.auth});

  final AuthStore auth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off,
                  size: 56,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Tidak dapat terhubung ke server',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  auth.lastError ??
                      'Periksa koneksi internet lalu coba lagi. Sesi Anda tetap tersimpan.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: auth.loading ? null : auth.retryBootstrap,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Coba lagi'),
                ),
                TextButton(
                  onPressed: auth.logout,
                  child: const Text('Keluar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
