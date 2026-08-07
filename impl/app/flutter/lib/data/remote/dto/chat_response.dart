/// DeepSeek 聊天补全响应 DTO。
/// 对照 Kotlin ChatResponse.kt（kotlinx.serialization，snake_case JSON 键，
/// ignoreUnknownKeys = true → Dart 侧同样只读已知键）。
class ChatCompletionResponse {
  const ChatCompletionResponse({this.id, this.choices = const [], this.usage});

  final String? id;
  final List<Choice> choices;
  final Usage? usage;

  factory ChatCompletionResponse.fromJson(Map<String, Object?> json) =>
      ChatCompletionResponse(
        id: json['id'] as String?,
        choices: [
          for (final c in (json['choices'] as List? ?? const []))
            Choice.fromJson((c as Map?)?.cast<String, Object?>() ?? const {}),
        ],
        usage: json['usage'] == null
            ? null
            : Usage.fromJson((json['usage'] as Map).cast<String, Object?>()),
      );
}

class Choice {
  const Choice({this.index = 0, required this.message, this.finishReason});

  final int index;
  final ChatResponseMessage message;
  final String? finishReason;

  factory Choice.fromJson(Map<String, Object?> json) => Choice(
        index: (json['index'] as num?)?.toInt() ?? 0,
        message: json['message'] == null
            ? const ChatResponseMessage()
            : ChatResponseMessage.fromJson(
                (json['message'] as Map).cast<String, Object?>()),
        finishReason: json['finish_reason'] as String?,
      );
}

class ChatResponseMessage {
  const ChatResponseMessage({this.role = 'assistant', this.content = ''});

  final String role;
  final String content;

  factory ChatResponseMessage.fromJson(Map<String, Object?> json) =>
      ChatResponseMessage(
        role: (json['role'] as String?) ?? 'assistant',
        content: (json['content'] as String?) ?? '',
      );
}

class Usage {
  const Usage({this.promptTokens = 0, this.completionTokens = 0, this.totalTokens = 0});

  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  factory Usage.fromJson(Map<String, Object?> json) => Usage(
        promptTokens: (json['prompt_tokens'] as num?)?.toInt() ?? 0,
        completionTokens: (json['completion_tokens'] as num?)?.toInt() ?? 0,
        totalTokens: (json['total_tokens'] as num?)?.toInt() ?? 0,
      );
}
