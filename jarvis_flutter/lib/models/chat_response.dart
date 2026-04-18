class ClientAction {
  final String type;
  final String? url;
  final String? message;
  final String? appName;
  final String? action;
  final Map<String, dynamic> arguments;

  ClientAction({
    required this.type,
    this.url,
    this.message,
    this.appName,
    this.action,
    this.arguments = const <String, dynamic>{},
  });

  factory ClientAction.fromJson(Map<String, dynamic> json) {
    final rawArguments = json['arguments'];
    return ClientAction(
      type: json['type'] ?? '',
      url: json['url'],
      message: json['message'],
      appName: json['app_name'],
      action: json['action'],
      arguments: rawArguments is Map<String, dynamic>
          ? rawArguments
          : const <String, dynamic>{},
    );
  }
}

class ToolCallModel {
  final String type;
  final String toolName;
  final Map<String, dynamic> arguments;

  ToolCallModel({
    required this.type,
    required this.toolName,
    required this.arguments,
  });

  factory ToolCallModel.fromJson(Map<String, dynamic> json) {
    final rawArguments = json['arguments'];
    return ToolCallModel(
      type: json['type']?.toString() ?? '',
      toolName: json['tool_name']?.toString() ?? '',
      arguments: rawArguments is Map<String, dynamic>
          ? rawArguments
          : const <String, dynamic>{},
    );
  }
}

class ToolResultModel {
  final String toolName;
  final bool ok;
  final dynamic data;

  ToolResultModel({
    required this.toolName,
    required this.ok,
    this.data,
  });

  factory ToolResultModel.fromJson(Map<String, dynamic> json) {
    return ToolResultModel(
      toolName: json['tool_name']?.toString() ?? '',
      ok: json['ok'] == true,
      data: json['data'],
    );
  }

  String dataAsText() {
    final value = data;
    if (value == null) {
      return '';
    }
    return value.toString().trim();
  }
}

class ChatResponseModel {
  final String reply;
  final String transcript;
  final ClientAction? clientAction;
  final ToolCallModel? toolCall;
  final ToolResultModel? toolResult;

  ChatResponseModel({
    required this.reply,
    this.transcript = '',
    this.clientAction,
    this.toolCall,
    this.toolResult,
  });

  factory ChatResponseModel.fromJson(Map<String, dynamic> json) {
    return ChatResponseModel(
      reply: json['reply'] ?? 'Sem resposta',
      transcript: (json['transcript'] ?? '').toString(),
      toolCall: json['tool_call'] != null
          ? ToolCallModel.fromJson(json['tool_call'])
          : null,
      toolResult: json['tool_result'] != null
          ? ToolResultModel.fromJson(json['tool_result'])
          : null,
      clientAction: json['client_action'] != null
          ? ClientAction.fromJson(json['client_action'])
          : null,
    );
  }
}