class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://sekitarin.ckamal.com/api/v1',
  );

  static const String wsUrlOverride = String.fromEnvironment(
    'WS_URL',
    defaultValue: 'wss://sekitarinws.ckamal.com',
  );

  static Uri apiUri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(apiBaseUrl);
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    final prefix = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(
      path: '$prefix/$cleanPath',
      queryParameters: query == null || query.isEmpty ? null : query,
    );
  }

  static String get wsUrl {
    if (wsUrlOverride.isNotEmpty) {
      return wsUrlOverride;
    }
    final base = Uri.parse(apiBaseUrl);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    return Uri(
      scheme: scheme,
      host: base.host,
      port: 8090,
      path: '',
    ).toString();
  }

  // Firebase / FCM, supplied at build time:
  // --dart-define=FIREBASE_API_KEY=... --dart-define=FIREBASE_APP_ID=...
  // --dart-define=FIREBASE_MESSAGING_SENDER_ID=... --dart-define=FIREBASE_PROJECT_ID=...
  static const String firebaseApiKey =
      String.fromEnvironment('FIREBASE_API_KEY');
  static const String firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
  static const String firebaseMessagingSenderId =
      String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
  static const String firebaseProjectId =
      String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const String firebaseStorageBucket =
      String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
  static const String firebaseIosBundleId = String.fromEnvironment(
    'FIREBASE_IOS_BUNDLE_ID',
    defaultValue: 'net.emetrotel.sekitarApp',
  );

  static bool get firebaseConfigured =>
      firebaseApiKey.isNotEmpty &&
      firebaseAppId.isNotEmpty &&
      firebaseMessagingSenderId.isNotEmpty &&
      firebaseProjectId.isNotEmpty;

  static String absoluteUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    final base = Uri.parse(apiBaseUrl);
    return base.replace(path: path, query: null).toString();
  }
}
