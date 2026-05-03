import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis_flutter/services/api_service.dart';
import 'package:jarvis_flutter/services/log_service.dart';
import 'package:jarvis_flutter/services/routine_service.dart';

class _FakeRoutineApiService extends ApiService {
  Map<String, dynamic> runResult = <String, dynamic>{};

  @override
  Future<Map<String, dynamic>> runRoutine(String routineId) async {
    return runResult;
  }
}

void main() {
  setUp(() {
    LogService().clearLogs();
  });

  test(
    'RoutineService indica sucesso quando todos os passos correm bem',
    () async {
      final api = _FakeRoutineApiService()
        ..runResult = <String, dynamic>{
          'results': <Map<String, dynamic>>[
            {'step': 1, 'type': 'home_assistant_service', 'ok': true},
          ],
        };
      final service = RoutineService.test(api: api);

      final message = await service.runRoutine('routine-ok');

      expect(message, 'Rotina executada com 1 passo.');
      expect(service.error, isNull);
    },
  );

  test('RoutineService reporta falhas por passo sem fingir sucesso', () async {
    final api = _FakeRoutineApiService()
      ..runResult = <String, dynamic>{
        'results': <Map<String, dynamic>>[
          {'step': 1, 'type': 'home_assistant_service', 'ok': true},
          {'step': 2, 'type': 'home_assistant_service', 'ok': false},
        ],
      };
    final service = RoutineService.test(api: api);

    final message = await service.runRoutine('routine-fail');

    expect(message, 'A rotina terminou com 1 falha.');
    expect(service.error, 'A rotina terminou com 1 falha.');
  });
}
