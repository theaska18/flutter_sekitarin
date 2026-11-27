import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/api_client.dart';
import 'core/token_store.dart';
import 'core/ws_client.dart';
import 'services/push_service.dart';
import 'state/auth_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PushService.initialize();
  final api = ApiClient();
  final store = await TokenStore.create();
  final ws = WsClient();
  final auth = AuthStore(api, store, ws);
  await auth.bootstrap();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthStore>.value(value: auth),
      ],
      child: const SekitarApp(),
    ),
  );
}
