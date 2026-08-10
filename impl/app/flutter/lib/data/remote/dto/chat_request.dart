/// DeepSeek 聊天补全请求 DTO。
/// 对照 Kotlin ChatRequest.kt（kotlinx.serialization，snake_case JSON 键）。
class ChatMessage {
  const ChatMessage({required this.role, required this.content});

  /// "system" | "user" | "assistant"
  final String role;
  final String content;

  Map<String, Object?> toJson() => {'role': role, 'content': content};
}

class ChatCompletionRequest {
  const ChatCompletionRequest({
    required this.model,
    required this.messages,
    this.temperature = 0.7,
    this.maxTokens = 16384,
    this.stream = false,
  });

  final String model;
  final List<ChatMessage> messages;
  final double temperature;
  final int maxTokens;
  final bool stream;

  Map<String, Object?> toJson() => {
        'model': model,
        'messages': [for (final m in messages) m.toJson()],
        'temperature': temperature,
        'max_tokens': maxTokens,
        'stream': stream,
      };
}
