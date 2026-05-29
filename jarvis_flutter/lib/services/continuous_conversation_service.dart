class ContinuousConversationService {
  static const Set<String> stopPhrases = <String>{
    'parar escuta',
    'para escuta',
    'parar conversa',
    'terminar conversa',
    'desligar conversa continua',
    'desliga conversa continua',
    'parar de ouvir',
    'deixa de ouvir',
    'podes parar',
    'pode parar',
    'ja podes parar',
  };

  const ContinuousConversationService();

  bool shouldInterceptStopCommand({
    required bool continuousConversationEnabled,
    required bool isFollowUp,
    required bool overlayOnly,
  }) {
    if (overlayOnly) {
      return false;
    }

    if (continuousConversationEnabled) {
      return true;
    }

    return isFollowUp;
  }

  bool isStopCommand(String transcript) {
    final normalized = normalizeCommandText(transcript);
    if (normalized.isEmpty) {
      return false;
    }

    for (final phrase in stopPhrases) {
      if (normalized.contains(phrase)) {
        return true;
      }
    }
    return false;
  }

  String normalizeCommandText(String input) {
    const replacements = <String, String>{
      'á': 'a',
      'à': 'a',
      'ã': 'a',
      'â': 'a',
      'ä': 'a',
      'Á': 'a',
      'À': 'a',
      'Ã': 'a',
      'Â': 'a',
      'Ä': 'a',
      'é': 'e',
      'ê': 'e',
      'ë': 'e',
      'É': 'e',
      'Ê': 'e',
      'Ë': 'e',
      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ï': 'i',
      'Í': 'i',
      'Ì': 'i',
      'Î': 'i',
      'Ï': 'i',
      'ó': 'o',
      'ò': 'o',
      'õ': 'o',
      'ô': 'o',
      'ö': 'o',
      'Ó': 'o',
      'Ò': 'o',
      'Õ': 'o',
      'Ô': 'o',
      'Ö': 'o',
      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'Ú': 'u',
      'Ù': 'u',
      'Û': 'u',
      'Ü': 'u',
      'ç': 'c',
      'Ç': 'c',
      'Ã¡': 'a',
      'Ã ': 'a',
      'Ã£': 'a',
      'Ã¢': 'a',
      'Ã©': 'e',
      'Ãª': 'e',
      'Ã­': 'i',
      'Ã³': 'o',
      'Ã´': 'o',
      'Ãµ': 'o',
      'Ãº': 'u',
      'Ã§': 'c',
    };

    var normalized = input.toLowerCase();
    replacements.forEach((key, value) {
      normalized = normalized.replaceAll(key.toLowerCase(), value);
    });
    normalized = normalized.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized;
  }
}
