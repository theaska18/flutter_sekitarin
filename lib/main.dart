import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/api_client.dart';
import 'core/token_store.dart';
import 'core/ws_client.dart';
import 'services/call_service.dart';
import 'services/push_service.dart';
import 'state/auth_store.dart';
import 'state/chat_cache.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PushService.initialize();
  await ChatCache.init();
  final api = ApiClient();
  final store = await TokenStore.create();
  final ws = WsClient();
  final auth = AuthStore(api, store, ws);
  await auth.bootstrap();
  CallService.instance.attach(auth);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthStore>.value(value: auth),
      ],
      child: const SekitarApp(),
    ),
  );
}
