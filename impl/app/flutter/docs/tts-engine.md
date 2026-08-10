# TTS 引擎与资产安装

## 主题定位

阅读页全文朗读的语音合成引擎链：KittenTTS（本地神经网络 TTS）优先，初始化失败自动回退系统 TTS。本主题覆盖引擎组装、音色选择、模型/词典资产安装（marker 语义）、init 超时兜底四条线。

## 业务功能线

用户点击朗读后，阅读页控制器（ReadingController）通过 `ttsEngineProvider`（`lib/di/providers.dart`，FutureProvider 懒加载）取得引擎，调用 `speak` / `speakFullArticle` / `speakParagraphs` 发声。用户无感知的是语音由哪条引擎链发声——KittenTTS 可用则用 KittenTTS（本地合成、音质好、不依赖系统引擎），否则静默回退系统 TTS。

**音色选择**：KittenTTS 内置 8 个英语音色（Bella/Jasper/Luna/Bruno/Rosie/Hugo/Kiki/Leo）。设置页提供音色选择器（含逐音色试听），选择持久化到 `user_settings.tts_voice_id`，此后所有朗读入口（阅读页全文/段落/单词、参考页例句、词汇页单词）按当前音色发声。系统 TTS 回退时音色不生效（系统引擎没有音色概念），但功能不受影响。

朗读质量的两个坑（均已在代码层处理）：

1. **init 挂起**：CEPhonemizer 未传词典路径时，插件会从 `raw.githubusercontent.com` 下载 en_rules/en_list，http 无超时——国内网络下 `KittenTTS.create()` 永久挂起（CPU 0%），朗读链路被阻塞。解决：词典打包进 assets（`assets/kittentts_models/en_rules`、`en_list`，共 ~260KB），create() 显式传 `rulesPath`/`listPath` 直用本地文件，零网络依赖。
2. **音素器静默降级**：词典文件缺失时 `allowRuleBasedFallback` 兜底到纯规则音素器——发音质量明显变差（提交 9fb6c89 注释：「音质略差但可用」）。这就是 2026-08-10 真机「朗读效果变差」的根因：旧 APK 安装留下的 `.installed` marker 让新代码跳过资产拷贝，词典从未拷入。修复后 marker 不再是跳过拷贝的充分条件（见下）。

## 技术实现线

### 引擎组装（TtsEngineFactory）

```mermaid
flowchart TD
    A[工厂 create] --> B[构建 KittenTtsEngine]
    B --> C[kitten.init 带 45s 超时]
    C -->|TimeoutException| D[日志: init TIMEOUT<br/>按失败处理]
    C -->|成功| E{isAvailable}
    E -->|true| F[返回 KittenTtsEngine]
    E -->|false| G[SystemTtsEngine]
    D --> G
```

- `TtsEngineFactory.create()`（`lib/data/tts/tts_engine_factory.dart`）：`kittenInitTimeout = 45s`，超时接住后按失败回退系统 TTS，不阻塞朗读链路。
- KittenTtsEngine 惰性初始化（首次 speak 前触发 `init()`），失败记录 `_failureReason`，`speak` 返回 null。
- 会话层 `KittenTtsPluginSession` 包装插件：WAV 生成 → audioplayers 播放 → 完成/段落回调（段落回调细节见 [reading-paragraph-highlight.md](reading-paragraph-highlight.md)）。

### 音色选择（TtsVoice → 引擎 → SDK）

**枚举（`lib/domain/tts/tts_voice.dart`）**：`TtsVoice` 硬编码 8 个值，与 KittenTTS SDK 内置音色一一对应：

| 枚举值 | dbValue（落库） | label（UI） | 性别 |
|---|---|---|---|
| `bella` / `jasper` / `luna` / `bruno` / `rosie` / `hugo` / `kiki` / `leo` | 大写枚举名（`'BELLA'`…） | 中文·英文（如 `'贝拉 · Bella'`） | `isFemale` 逐值标注 |

`fromDbValue` 对未知值抛 `ArgumentError`（新 APK 遇旧值属 bug，快速暴露）；`sdkVoiceId => name`（小写枚举名 = SDK voice id）。

**透传链（每调用覆盖）**：`speak`/`speakFullArticle`/`speakParagraphs`/`pregenerateParagraphs` 的 `voice` 参数（`TtsVoice?`，null = 引擎默认 bella）沿引擎 → 会话 → SDK 逐层透传，KittenTTS SDK 的 `generate(text, voice: …)` **每次调用显式传 voice**，不依赖 config.defaultVoice——同一会话内切换音色立即生效。

```mermaid
sequenceDiagram
    participant UI as 设置页/阅读页
    participant E as TtsEngine.speak(voice?)
    participant S as KittenTtsSession(voice: String?)
    participant SDK as KittenTTS SDK generate
    UI->>E: speak(text, voice: hugo)
    E->>S: speak(text, voice: hugo.sdkVoiceId)  // null → 不传，SDK 用默认
    S->>SDK: generate(text, voice: 'hugo')
    S-->>UI: 播放/回调
```

- **SystemTtsEngine 忽略 voice**：系统引擎无音色概念，参数仅接受不消费（契约测试断言兼容）。
- **缓存键含音色维度**：`tts_cache` 加 `voice_id` 列，UNIQUE 联合 `(article_paragraph_id, word_id, speed, voice_id)`、文件名 `p_<id>_<speed>_<VOICE>.wav`——不同音色各自缓存，切换音色不互相污染。方法签名统一 `voice: TtsVoice voice = TtsVoice.bella`（非空默认），引擎/会话层的 `null` 语义在缓存调用点归一为 `TtsVoice.bella`。
- **当前音色 Provider（`lib/di/providers.dart`）**：`currentTtsVoiceProvider = FutureProvider<TtsVoice>`，读 `user_settings.tts_voice_id`（缺省 bella）。设置页 `updateTtsVoice` 成功后 `ref.invalidate(currentTtsVoiceProvider)` 使缓存失效——FutureProvider 结果缓存后不自动重算，不 invalidate 则参考页/词汇页继续读旧音色。参考/词汇页在 speak 时 `ref.read(currentTtsVoiceProvider).valueOrNull ?? TtsVoice.bella`（**read 而非 watch**：闭包内 watch 会注册依赖，voice 变化触发 StateNotifierProvider 重建 → dispose 后 use-after-dispose，实测崩溃）。阅读页不走 provider，按文章加载 settings 时读入 `ReadingUiState.ttsVoice`。
- **设置页**：`_VoicePickerDialog` 8 行单选（喇叭图标逐音色试听，固定例句 `'Hi, this is <EnglishName> speaking.'`，播放中再点即停；关闭弹窗即停掉试听），选择即持久化 + invalidate provider。

### 资产安装（installModelAssets）

首次 init 时把 4 个资产从 Flutter assets 解压到应用支持目录（Android 上为 `files/kittentts/models/`）：

```
assets/kittentts_models/           →  files/kittentts/models/
  kitten_tts_micro_v0_8.onnx (41MB)   ├── .installed（marker，内容 "1"）
  voices.npz (3MB)                    ├── kitten_tts_micro_v0_8.onnx
  en_rules (161KB)                    ├── voices.npz
  en_list (102KB)                     ├── en_rules
                                      └── en_list
```

**marker 语义（2026-08-10 修复后）**：`.installed` 存在 **且所有期望文件齐全** 才跳过拷贝。marker 存在但文件缺失时必须重新解压。

```mermaid
flowchart TD
    A[installModelAssets] --> B[创建 models 目录]
    B --> C{marker 存在 &&<br/>4 个文件齐全}
    C -->|true| D[跳过拷贝, 返回目录]
    C -->|false| E[遍历 4 资产: bundle.load → 写文件]
    E --> F[写 marker]
    F --> D
```

**为什么不能只看 marker**：词典打包进 assets（9fb6c89）之前安装的旧 marker 会让新代码跳过拷贝，词典缺失 → CEPhonemizer 静默降级为规则音素器 → 音质变差，且无任何报错。修复（2026-08-10）：跳过条件改为 marker + 文件完整性双重校验，未来新增任何资产（新模型、新词典）都会触发重新拷贝。

**测试注入点**：`basePathOverride`（根目录覆盖，绕过 path_provider）+ `bundleOverride`（内存 AssetBundle，绕过 rootBundle）。测试见 `test/data/tts/install_model_assets_test.dart`（全新目录拷贝 / stale marker 补齐 / 文件齐全跳过三用例）。

## 数据模型线

- 资产文件为二进制（onnx 模型、npz 音色、词典文本），无数据库实体。
- 朗读音频缓存见 TtsCacheManager（段落级 WAV，FIFO 50MB，表 `tts_cache`，缓存键含 `voice_id` 维度——见上文「缓存键含音色维度」）。
- 音色选择持久化在 `user_settings.tts_voice_id`（`TEXT NOT NULL`，dbValue 大写枚举名，缺省由应用代码填 `'BELLA'`；开发期补列路径用 `DEFAULT 'BELLA'`，见 [database-schema.md](database-schema.md) 打开自愈一节）。

## 错误处理与边界

| 场景 | 处理 |
|------|------|
| KittenTTS init 超时（45s） | 回退系统 TTS，日志记录，不阻塞朗读 |
| KittenTTS init 抛错 | `_failureReason` 记录具体原因，speak 返回 null / 回退系统 TTS |
| 词典文件缺失（旧 marker / 手动删除） | 重新拷贝补齐（marker+文件双重校验）；CEPhonemizer 侧仍有规则音素器兜底 |
| 音色参数为 null / 未知值 | 引擎/会话层归一到默认 bella（`TtsVoice.bella`），朗读不中断 |
| `tts_voice_id` 读到未知 dbValue | `fromDbValue` 抛 `ArgumentError`（上游 provider 层兜底 bella，见 currentTtsVoiceProvider） |
| 系统 TTS 回退 | voice 被忽略（系统引擎无音色概念），其余功能不受影响 |
| 首读耗时 | 首次 init 需解压 41MB 模型 + 词典，慢 1-2 秒属正常；marker 校验通过后为零拷贝 |

## 测试覆盖

- `test/data/tts/install_model_assets_test.dart`：marker 三语义用例（本次新增）
- `test/data/tts/kitten_tts_engine_test.dart`：init/speak/回调透传/失败路径（fake session）
- `test/data/tts/tts_engine_factory_test.dart`：Kitten 可用 / 失败回退 / 双失败不可用
- `test/data/tts/system_tts_engine_test.dart`、`tts_engine_contract_test.dart`：系统引擎与契约（含忽略 voice）
- `test/domain/tts/tts_voice_test.dart`：枚举 dbValue/label/性别/`fromDbValue` 异常（SDK 交叉验证 8/8）
- `test/di/current_tts_voice_provider_test.dart`：settings 音色读取 + 缺省 bella
- `test/ui/settings/settings_controller_test.dart` / `settings_screen_test.dart`：音色选择持久化 + 试听/停播 + provider invalidate
- 阅读页/参考页/词汇页测试：voice 透传到 engine（fake 断言 lastVoice）
- 真机验证：2026-08-10 修复后 init 0.7s、词典拷入后音质恢复；2026-08-09 init 挂起修复时验证 7 段全文朗读正常
