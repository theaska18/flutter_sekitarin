class AppConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://sekitarin.ckamal.com/api/v1',
  );

  static const String wsUrlOverride = String.fromEnvironment(
    'WS_URL',
    defaultValue: 'ws://sekitarinws.ckamal.com',
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

  static String absoluteUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    final base = Uri.parse(apiBaseUrl);
    return base.replace(path: path, query: null).toString();
  }
}
