# KittenTTS 音色（Voice）调研报告

> 调研日期：2026-08-10。任务：调研 Contexta 使用的 KittenTTS 有哪些可用音色，为将来"音色选择"功能提供依据。
> 本文件为临时调研文档，功能落地后可删除。

## 1. 项目当前 TTS 集成方式与音色现状

### 1.1 依赖与资产

- 包：`kittentts: ^0.1.0`（`impl/app/flutter/pubspec.yaml:20`），仓库 `KittenML/KittenTTS-flutter`（pub.dev 已发布，包内 pubspec.yaml 声明 homepage/repository）。
- 模型资产打包在 Flutter assets：`assets/kittentts_models/`（`pubspec.yaml:54`）：
  - `kitten_tts_micro_v0_8.onnx`（41,384,970 字节，约 39.5MB）——micro 档模型
  - `voices.npz`（3,278,902 字节，约 3.1MB）——全部音色的嵌入文件
  - `en_rules`（161KB）、`en_list`（102KB）——CEPhonemizer 词典（见 3.3）

### 1.2 当前音色使用方式：硬编码

- 引擎初始化时 `KittenTTSConfig.defaultVoice: kit.voice.bella` 写死为 Bella（`impl/app/flutter/lib/data/tts/kitten_tts_session.dart:126`）。
- 所有合成调用 `_engine.generate(text, speed: speed)` / `_engine.stream(text, speed: speed)` 均**不传 voice 参数**（kitten_tts_session.dart 全文 6 处：第 239/350/371/475/599/775 行附近），因此全部朗读实际使用默认音色 Bella。
- 设置页只有"朗读语速"（`UserSettings.ttsSpeed`，0.8|1.0|1.2），**没有音色配置项**（`lib/domain/model/user_settings.dart:12`；`settings_screen.dart` 中"朗读语速/自动朗读"两项）。
- 朗读缓存键为 `(articleParagraphId, speed)`，**不含音色**（`lib/data/tts/tts_cache_manager.dart:43-46, 98`）——将来加音色功能必须改，否则切音色后命中旧音色缓存。
- 系统 TTS 回退链：KittenTTS init 失败/超时时回退 `flutter_tts`（SystemTtsEngine），见主题文档 `impl/app/flutter/docs/tts-engine.md`。

## 2. KittenTTS 音色清单（8 个内置音色）

### 2.1 总览表

| 音色 ID | 显示名 | 性别 | 嵌入键（voices.npz） | 角色特征（官方描述） |
|---------|--------|------|----------------------|----------------------|
| `bella` | Bella | 女 | `expr-voice-2-f` | Warm and expressive（温暖、表现力强） |
| `jasper` | Jasper | 男 | `expr-voice-2-m` | Clear and conversational（清晰、口语化） |
| `luna` | Luna | 女 | `expr-voice-3-f` | Calm and smooth（平静、流畅） |
| `bruno` | Bruno | 男 | `expr-voice-3-m` | Deep and steady（低沉、稳健） |
| `rosie` | Rosie | 女 | `expr-voice-4-f` | Bright and friendly（明亮、友好） |
| `hugo` | Hugo | 男 | `expr-voice-4-m` | Authoritative（权威感） |
| `kiki` | Kiki | 女 | `expr-voice-5-f` | Lively and energetic（活泼、有活力） |
| `leo` | Leo | 男 | `expr-voice-5-m` | Relaxed and natural（放松、自然） |

来源：包内 `lib/src/kitten_voice.dart`（ID/嵌入键/性别映射，第 5-79 行）、包内 `doc/reference/models.md`（角色特征表）、核心仓库 README（`KittenML/KittenTTS`）。

结构特征：8 个音色 = **4 对（voice-2 ~ voice-5）×（女 f / 男 m）**，即 4 女 4 男。性别判定代码：`isFemaleVoice()`（kitten_voice.dart:78-79）。

### 2.2 音色属性

- **语言**：全部为**英语（英式/美式均可）音色**。KittenTTS 当前**仅支持英文**（详见 3.4）。
- **语速**：`speed` 参数 0.5–2.0（config 解析时 clamp，`lib/src/kitten_tts_config.dart:93`）。micro/mini 模型下所有音色 `speedPrior = 1.0`，nano 下 hugo=0.9、其余 0.8（`lib/src/kitten_model.dart:79-89`）——项目用 micro，音色不影响语速。
- **音质档位与音色无关**：音色是统一的嵌入（style vector），由模型档位决定合成质量（见 2.3）。
- 输出采样率 24kHz（`lib/src/kitten_tts_config.dart:7`）。

### 2.3 配套模型档位（与音色正交）

| 模型 ID | 参数量 | 下载大小 | HF 仓库 | 说明 |
|---------|--------|----------|---------|------|
| `nano-int8` | 15M | 25 MB | KittenML/kitten-tts-nano-0.8-int8 | 最小 |
| `nano` | 15M | 56 MB | KittenML/kitten-tts-nano-0.8 | |
| `micro` | 40M | 41 MB | KittenML/kitten-tts-micro-0.8 | **项目当前使用** |
| `mini` | 80M | 80 MB | KittenML/kitten-tts-mini-0.8 | 质量最高 |

来源：包内 `doc/reference/models.md`、`lib/src/kitten_model.dart`。每个模型仓库各带一份同一格式的 `voices.npz`（kitten_model.dart:60-63）。

## 3. 底层引擎与音色机制

### 3.1 KittenTTS 是什么、基于什么

**KittenTTS 是 KittenML（stellonlabs）自研的轻量神经网络 TTS，不是基于 piper / sherpa-onnx / espeak-ng 的套壳**：

- 核心仓库 `KittenML/KittenTTS`（Python）README：「open-source, lightweight text-to-speech library built on ONNX」「15M 到 80M 参数、25-80MB、CPU 推理」。
- 模型输入为三样：`input_ids`（音素 token 序列）+ `style`（音色嵌入）+ `speed`（语速）——自定义架构（来源：`kittentts/onnx_model.py` 的 `_prepare_inputs`）。
- Flutter SDK 通过 `flutter_onnxruntime` 在端上跑同一 ONNX 模型（包 pubspec.yaml: `flutter_onnxruntime: ^1.7.0`）。
- 音素化（前端）：
  - Python 版：espeak-ng，`EspeakBackend(language="en-us")`（onnx_model.py）。
  - Flutter 版：**CEPhonemizer**（Dart FFI），词典即 espeak-ng 的 `en_rules`/`en_list`（`lib/src/phonemizer/ce_phonemizer.dart:21-26` 的 defaultRulesUrl 指向 espeak-ng 仓库 dictsource）——这正是项目打包进 assets 的两个文件。

### 3.2 音色是怎么提供的

- 音色 = `voices.npz` 里的**风格嵌入矩阵**，每音色一个 `expr-voice-*` 键；合成时按文本长度取矩阵某行作为 `style` 输入（Python 侧 `ref_id = min(len(text), ...)`，`ref_s = self.voices[voice][ref_id:ref_id+1]`；Flutter 侧 `loadNPZ()` 把全部 `.npy` 键读进 map，`voiceEmbeddingKey(voice)` 查键）。
- 提供机制：**内置随模型分发**。两种获取路径：① 首次运行从 HF 下载到缓存（SDK 默认，国内网络不可用）；② 本地文件（`KittenTTSModelFiles(onnxPath, voicesPath)`——**项目用的就是这条**，模型资产已打包进 APK）。
- 运行时切换：`generate / speak / stream` 每次调用都可传 `voice:` 覆盖（`lib/src/kitten_tts.dart:97-199`），不传则用 `config.defaultVoice`。**无需重建引擎即可切换音色**。
- **自定义音色**：无公开的语音克隆/训练工具链；官方商业化渠道提供 custom voice development（核心 README "Commercial Support"）。Python 侧构造函数支持注入 `voice_aliases`/`speed_priors`（onnx_model.py），即理论上可给 voices.npz 增加新嵌入键，但社区无自助方案。

### 3.4 语言支持（关键结论）

**当前仅支持英文**，依据：

1. 核心仓库 README Roadmap 明确列出待办：「Release multilingual TTS」——多语言尚未发布。
2. Python 音素化写死 `language="en-us"`（espeak-ng）；文本预处理 `normalize_text(text, locale="en-US")`。
3. Flutter 端 CEPhonemizer 只有 `dialect: 'en-us'` 与英文词典；TextCleaner 字符表为英文字母 + IPA 音标（onnx_model.py）。

即：8 个音色都是英语音色；**中文朗读 KittenTTS 目前不支持**。

## 4. 底层音色生态（补充调研：音色选择扩展方向的备选）

Contexta 面向中文用户读英文文章，当前 KittenTTS 音色选择只有 8 个英语音色。若将来要更多音色或中文语音，可参考以下生态（均为离线/端侧方案）：

### 4.1 sherpa-onnx（k2-fsa，综合最强）

- 原生支持大量 VITS 系模型：piper 全量转换版（30+ 语言、100+ 音色）、matcha、kokoro（含中文）、F5-TTS、melo-tts-zh_en（中英双语）、vits-zh-hf 系列（中文游戏角色音色：bronya/echo/keqing/zenyatta 等）。
- **原生支持 KittenTTS 模型**：`kitten-nano-en-v0_1-fp16`（8 音色 4 男 4 女，由 KittenML/kitten-tts-nano-0.1 转换，见 sherpa 仓库 `docs/source/onnx/tts/pretrained_models/kitten.rst`）；并发布 Android TTS 引擎 APK（可替换系统 TTS 供第三方 App 调用）。
- Dart 绑定：pub.dev `sherpa_onnx`（含 `sherpa_onnx_android` 等平台包）。
- 参考：https://github.com/k2-fsa/sherpa-onnx 、模型清单 https://github.com/k2-fsa/sherpa-onnx/releases/tag/tts-models

### 4.2 Piper（rhasspy）

- VITS 架构 + espeak-ng 音素化，44 个语言 locale（含 zh_CN），每音色分 x_low/low/medium/high 档。
- 英语代表性音色：en_US 的 lessac / amy / libritts_r / hfc_female / hfc_male / glados 等；en_GB 的 alan / northern_english_male / southern_english_female / jenny_dioco 等。
- 中文：zh_CN 的 huayan（medium 已在 sherpa-onnx 发布清单中：`vits-piper-zh_CN-huayan-medium`）、xiaohan、xiaomeng、xiaoxiao 等。
- 参考：https://huggingface.co/rhasspy/piper-voices 、https://github.com/rhasspy/piper

### 4.3 项目内已有资源

- `flutter_tts`（系统 TTS）已作为 KittenTTS 的回退引擎，系统级音色选择（`setVoice`）与语言切换能力现成。

## 5. 对项目添加"音色选择"功能的建议

### 5.1 结论：可行，且是低成本改动

- 8 个音色**全部已随 voices.npz 打进 APK**（3.1MB），零新增资产下载。
- SDK API 支持每次合成调用传 `voice:` 覆盖，**无需重建/重启引擎**（见 3.2）。
- 音色切换对合成质量无影响（质量由模型档位决定，micro 不变）。

### 5.2 建议实现路径

1. **数据层**：`UserSettings` 增加 `ttsVoiceId`（默认 `'bella'`）；`settings_tables.dart` 加列。⚠️ 注意 MIGRATION 纪律：当前未发布（`tool/db_version` = 0），结构变更并入 `tool/migrations/001-init.sql` 同步更新（CLAUDE.md 数据库规则；发布后则须写编号迁移脚本 + drift onUpgrade 镜像）。
2. **引擎层**：`KittenTtsSession` 的 generate/stream 调用透传 voice——`kitten_tts_session.dart` 中 6 处 `_engine.generate(text, speed: speed)` 改为 `generate(text, voice: <voice>, speed: speed)`（session 构造时注入用户所选音色，或 speak* 方法带 voice 参数）。引擎创建处 `defaultVoice: kit.voice.bella`（:126）改为读设置（或保持默认 + 逐调用透传，推荐后者）。
3. **缓存层（必须）**：`tts_cache_manager.dart` 缓存键 `(paragraphId, speed)` 需加入 voice 维度（表加 `voice_id` 列；文件名 `p_{id}_{speed}.wav` 同步带 voice），否则切换音色后会播放旧音色的缓存音频。
4. **UI 层**：设置页新增"朗读音色"选择项，8 选 1；SDK 自带现成模式——包内 `example/basic/lib/main.dart:650-691` 的 `_VoiceSelector`（DropdownButtonFormField 遍历 `allKittenTTSVoiceIds` + `voiceDisplayName`），可直接参考。
5. **回退链**：系统 TTS 分支可选地提供系统音色选择（flutter_tts），非必需。

### 5.3 边界与注意

- 音色仅作用于**英文**朗读；KittenTTS 不支持中文（3.4）。若将来要中文朗读，需引入 sherpa_onnx（melo-tts-zh_en / piper zh_CN）或走系统 TTS。
- KittenTTS 是 developer preview，API 可能变动（包 README 声明）；音色 ID 列表以包内 `allKittenTTSVoiceIds` 为准，UI 不硬编码。
- 换音色时 TTS 缓存内容与音色强相关，缓存淘汰策略（FIFO 50MB）不变，仅键扩展。

## 6. 参考来源

| 主题 | 来源 |
|------|------|
| Flutter SDK（本调研的主要依据，与项目锁定版本 0.1.0 一致） | `~/.pub-cache/hosted/pub.flutter-io.cn/kittentts-0.1.0/`：README.md、doc/reference/models.md、lib/src/kitten_voice.dart、kitten_model.dart、kitten_tts_config.dart、kitten_tts.dart、loader/npz_loader.dart、phonemizer/ce_phonemizer.dart、example/basic/lib/main.dart |
| 核心模型（Python） | https://github.com/KittenML/KittenTTS （README + kittentts/onnx_model.py、get_model.py、preprocess.py） |
| 模型仓库（HF，本机直连不可达，内容经 GitHub 源码交叉验证） | https://huggingface.co/KittenML/kitten-tts-micro-0.8 （及 nano/mini 系列） |
| sherpa-onnx 对 KittenTTS/piper 的支持 | https://github.com/k2-fsa/sherpa 的 docs/source/onnx/tts/pretrained_models/kitten.rst、piper.rst；https://github.com/k2-fsa/sherpa-onnx/releases/tag/tts-models |
| Piper 音色生态 | https://huggingface.co/rhasspy/piper-voices 、https://github.com/rhasspy/piper 、https://rhasspy.github.io/piper-samples （试听） |
| 项目代码 | `impl/app/flutter/pubspec.yaml:20,54`、`lib/data/tts/kitten_tts_session.dart:126`、`lib/data/tts/tts_cache_manager.dart:43-46,98`、`lib/domain/model/user_settings.dart:12`、`docs/tts-engine.md` |
