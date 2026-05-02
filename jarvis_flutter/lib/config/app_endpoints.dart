class AppEndpoints {
  static const String apiToken = String.fromEnvironment(
    'JARVIS_API_TOKEN',
    defaultValue: '',
  );
  static String _runtimeApiToken = '';

  static const String apiBaseUrl = String.fromEnvironment(
    'JARVIS_API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  static const String agentBaseUrl = String.fromEnvironment(
    'JARVIS_AGENT_BASE_URL',
    defaultValue: 'http://127.0.0.1:5001',
  );

  static String apiUnavailableMessage() {
    return _connectionHint(apiBaseUrl, 'JARVIS_API_BASE_URL');
  }

  static String agentUnavailableMessage() {
    return _connectionHint(agentBaseUrl, 'JARVIS_AGENT_BASE_URL');
  }

  static void setRuntimeApiToken(String token) {
    _runtimeApiToken = token.trim();
  }

  static void clearRuntimeApiToken() {
    _runtimeApiToken = '';
  }

  static String _connectionHint(String baseUrl, String dartDefine) {
    final uri = Uri.tryParse(baseUrl);
    final host = uri?.host ?? '';
    if (host == '127.0.0.1' || host == 'localhost') {
      final portSuffix = uri?.hasPort == true ? ':${uri!.port}' : '';
      return 'Nao consegui ligar a $baseUrl. Num telemovel ou emulador, define '
          '--dart-define=$dartDefine=http://IP_DO_PC$portSuffix.';
    }

    return 'Nao consegui ligar a $baseUrl. Verifica se o servico esta ativo e acessivel.';
  }

  static Map<String, String> apiHeaders({bool includeJsonContentType = false}) {
    final headers = <String, String>{};
    if (includeJsonContentType) {
      headers['Content-Type'] = 'application/json';
    }
    final token = _runtimeApiToken.trim().isNotEmpty
        ? _runtimeApiToken.trim()
        : apiToken.trim();
    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }
}
