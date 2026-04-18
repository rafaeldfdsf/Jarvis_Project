import 'package:flutter/foundation.dart';
import '../models/log_entry.dart';

class LogService extends ChangeNotifier {
  // Singleton:
  // garante que toda a app usa a mesma instância do serviço de logs
  static final LogService _instance = LogService._internal();

  factory LogService() {
    return _instance;
  }

  LogService._internal();

  // Lista interna com todos os logs
  final List<LogEntry> _logs = [];

  // Getter para leres os logs fora da classe
  List<LogEntry> get logs => List.unmodifiable(_logs);

  // Método para adicionar um novo log
  void addLog(String type, String message) {
    _logs.insert(
      0,
      LogEntry(type: type, message: message, timestamp: DateTime.now()),
    );

    // Notifica a UI para atualizar automaticamente
    notifyListeners();
  }

  // Método para limpar todos os logs
  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }
}
