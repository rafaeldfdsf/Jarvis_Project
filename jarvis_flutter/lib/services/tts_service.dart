import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;

import 'package:jarvis_flutter/config/app_endpoints.dart';
import 'package:jarvis_flutter/services/log_service.dart';

class TtsService {
  final AudioPlayer _player = AudioPlayer();
  final String baseUrl = AppEndpoints.apiBaseUrl;
  final LogService _logService = LogService();

  Future<void> init() async {
    _logService.addLog('INFO', 'TtsService inicializado.');
  }

  void setOnComplete(void Function() handler) {
    _player.onPlayerComplete.listen((event) {
      _logService.addLog('INFO', 'Reproducao TTS terminada.');
      handler();
    });
  }

  Future<void> speak(String text) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) {
      _logService.addLog('WARN', 'TTS ignorado porque o texto veio vazio.');
      return;
    }

    StreamSubscription<void>? completionSubscription;

    try {
      _logService.addLog('INFO', 'A enviar texto para /tts.');

      final response = await http
          .post(
            Uri.parse('$baseUrl/tts'),
            headers: AppEndpoints.apiHeaders(includeJsonContentType: true),
            body: jsonEncode({'text': cleanText}),
          )
          .timeout(const Duration(seconds: 15));

      _logService.addLog(
        'INFO',
        'Resposta recebida do backend. Status code: ${response.statusCode}',
      );

      if (response.statusCode != 200) {
        _logService.addLog('ERROR', 'Erro HTTP no /tts: ${response.body}');
        return;
      }

      final data = jsonDecode(response.body);
      final audioBase64 = data['audio'];

      if (audioBase64 is! String || audioBase64.isEmpty) {
        _logService.addLog('ERROR', 'O backend respondeu sem audio valido.');
        return;
      }

      final bytes = base64Decode(audioBase64);
      _logService.addLog('INFO', 'Audio convertido de base64 com sucesso.');

      final playbackCompleted = Completer<void>();
      await _player.stop();
      completionSubscription = _player.onPlayerComplete.listen((event) {
        if (!playbackCompleted.isCompleted) {
          _logService.addLog('INFO', 'Reproducao TTS terminada.');
          playbackCompleted.complete();
        }
      });

      await _player.play(BytesSource(bytes));
      _logService.addLog('INFO', 'Reproducao do audio iniciada.');
      await playbackCompleted.future.timeout(
        const Duration(minutes: 2),
        onTimeout: () {
          _logService.addLog(
            'WARN',
            'Tempo limite atingido a aguardar pelo fim do TTS.',
          );
        },
      );
    } on TimeoutException {
      _logService.addLog('ERROR', AppEndpoints.apiUnavailableMessage());
    } catch (error) {
      _logService.addLog('ERROR', 'Falha no speak(): $error');
    } finally {
      await completionSubscription?.cancel();
    }
  }

  Future<void> stop() async {
    await _player.stop();
    _logService.addLog('WARN', 'Reproducao de audio interrompida.');
  }
}
