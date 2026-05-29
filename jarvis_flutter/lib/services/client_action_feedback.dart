import '../models/chat_response.dart';

String buildClientActionFailureMessage(
  ClientAction action, {
  String? detail,
}) {
  final cleanDetail = (detail ?? '').trim();
  final target = _resolveActionTarget(action);

  String baseMessage;
  switch (action.type) {
    case 'open_app':
      baseMessage = target.isNotEmpty
          ? 'Nao consegui abrir $target.'
          : 'Nao consegui abrir a aplicacao pedida.';
      break;
    case 'open_url':
      baseMessage = 'Nao consegui abrir o link pedido.';
      break;
    case 'pc_action':
      final actionName = (action.action ?? '').trim().toLowerCase();
      if (actionName == 'youtube_play') {
        baseMessage = 'Nao consegui por a musica a tocar no YouTube.';
      } else if (actionName == 'youtube_search') {
        baseMessage = 'Nao consegui pesquisar isso no YouTube.';
      } else if (actionName == 'open_app' && target.isNotEmpty) {
        baseMessage = 'Nao consegui abrir $target.';
      } else if (actionName == 'open_url') {
        baseMessage = 'Nao consegui abrir o link pedido.';
      } else {
        baseMessage = 'Nao consegui executar essa acao no dispositivo.';
      }
      break;
    default:
      baseMessage = 'Nao consegui executar essa acao no dispositivo.';
      break;
  }

  if (cleanDetail.isEmpty) {
    return baseMessage;
  }

  return '$baseMessage Detalhe: $cleanDetail';
}

String _resolveActionTarget(ClientAction action) {
  final appName = (action.appName ?? '').trim();
  if (appName.isNotEmpty) {
    return appName;
  }

  for (final key in <String>['app_name', 'url', 'query', 'window_title']) {
    final value = action.arguments[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) {
      return value;
    }
  }

  return '';
}
