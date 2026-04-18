class LogEntry {
  // Tipo do log: INFO, ERROR, WARN, DEBUG
  final String type;

  // Mensagem do log
  final String message;

  // Momento em que o log foi criado
  final DateTime timestamp;

  LogEntry({
    required this.type,
    required this.message,
    required this.timestamp,
  });
}
