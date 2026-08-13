class AppConfig {
  static const deepSeekApiKey = String.fromEnvironment('DEEPSEEK_API_KEY');
  static const deepSeekModel = String.fromEnvironment('DEEPSEEK_MODEL', defaultValue: 'deepseek-v4-flash');
  static const deepSeekBaseUrl = String.fromEnvironment('DEEPSEEK_BASE_URL', defaultValue: 'https://api.deepseek.com');
  /// 服务端 API origin（无尾斜杠，如 https://api.example.com）；
  /// ServerApiClient 以 `$serverBaseUrl$path` 拼接请求 URL。
  static const serverBaseUrl = String.fromEnvironment('SERVER_BASE_URL');
  static const feishuWebhookUrl = String.fromEnvironment('FEISHU_WEBHOOK_URL');
  static const feishuSignSecret = String.fromEnvironment('FEISHU_SIGN_SECRET');
  static const llmTimeoutMs = int.fromEnvironment('LLM_TIMEOUT_MS', defaultValue: 120000);
  static const llmMaxRetries = int.fromEnvironment('LLM_MAX_RETRIES', defaultValue: 3);
  static const llmMaxRetryAfterSeconds = int.fromEnvironment('LLM_MAX_RETRY_AFTER_SECONDS', defaultValue: 30);
}
