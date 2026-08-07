class AppConfig {
  static const deepSeekApiKey = String.fromEnvironment('DEEPSEEK_API_KEY');
  static const deepSeekBaseUrl = String.fromEnvironment('DEEPSEEK_BASE_URL', defaultValue: 'https://api.deepseek.com');
  static const feishuWebhookUrl = String.fromEnvironment('FEISHU_WEBHOOK_URL');
  static const feishuSignSecret = String.fromEnvironment('FEISHU_SIGN_SECRET');
  static const llmTimeoutMs = int.fromEnvironment('LLM_TIMEOUT_MS', defaultValue: 120000);
}
