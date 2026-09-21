import 'dart:convert';
import 'dart:io';

import 'package:contexta/data/tts/kitten_tts_engine.dart';
import 'package:contexta/ui/reference/reference_data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kittentts/kittentts_flutter.dart' as kit;
import 'package:path_provider/path_provider.dart';

/// **生成用例（不是回归测试）**：字母读音行里那些「例词取自站点」的行
/// （X 的 box / exam / xylophone）没有随包录音，用 App 自带的 KittenTTS
/// （micro 模型 + bella 音色，与参考页发音同一个嗓子）合成成 mp3，
/// 落到设备的外部文件目录，再 `adb pull` 回 `assets/phonetics/`。
///
/// 为什么不用运行时 TTS：连播要精确等一段播完再进下一段，而 TTS 没有播完回调
/// （见 docs/reference-alphabet.md）；预生成成文件后，这些例词与音标录音走
/// 同一条播放链路。
///
/// 跑法（模拟器/真机，debug 包）：
/// ```
/// flutter test integration_test/generate_letter_words_test.dart -d <device>
/// adb pull /sdcard/Android/data/com.ak.contexta/files/letter_words /tmp/letter_words
/// # 设备上只出 wav（插件不带 mp3 编码器，见下），本地转码后拷进 assets：
/// for f in /tmp/letter_words/*.wav; do
///   afconvert -f mp3 -d '.mp3' -b 64000 "$f" "assets/phonetics/$(basename "${f%.wav}").mp3"
/// done
/// ```
/// 再把 `letter_words/manifest-fragment.json` 的内容并进
/// `assets/phonetics/manifest.json` 的 `letterWords` 段。
/// `reference_data_test` 会守门：自带例词的行必须在 manifest 里有对应条目、
/// 词对得上、文件真实存在且非空。
///
/// **为什么落地是 wav**：kittentts 插件不带 mp3 编码器
/// （`mp3Data()` 抛 UnsupportedError：MP3 编码要 GPL/LGPL 的编解码代码），
/// 所以设备上出 24kHz wav，转 mp3 这一步放在本地做。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('合成字母读音行的站点例词（TTS → mp3 + manifest 片段）',
      (tester) async {
    // 与 KittenTtsPluginSession.create 同一套配置（模型 / 音色 / 词典路径）
    final modelsDir = await installModelAssets('assets/kittentts_models');
    final engine = await kit.KittenTTS.create(
      config: kit.KittenTTSConfig(
        model: kit.model.micro,
        defaultVoice: kit.voice.bella,
        storageDirectory: modelsDir.path,
        modelFiles: kit.KittenTTSModelFiles(
          onnxPath: '${modelsDir.path}/kitten_tts_micro_v0_8.onnx',
          voicesPath: '${modelsDir.path}/voices.npz',
        ),
        phonemizer: kit.CEPhonemizer(
          rulesPath: '${modelsDir.path}/en_rules',
          listPath: '${modelsDir.path}/en_list',
          allowRuleBasedFallback: false,
        ),
        analytics: false,
      ),
    );

    // 只处理「自带例词」的行——其余行的例词录音在音标库里已经有了
    final targets = [
      for (final group in letterSounds)
        for (final row in soundRowsOf(group.letter))
          if (row.isOwnExample) row,
    ];
    expect(targets, isNotEmpty, reason: '没有自带例词的读音行？数据变了吧');

    final outDir = Directory(
      '${(await getExternalStorageDirectory())!.path}/letter_words',
    );
    await outDir.create(recursive: true);

    final fragment = <Map<String, String>>[];
    for (final (index, row) in targets.indexed) {
      final base = 'l${(index + 1).toString().padLeft(2, '0')}';
      final result = await engine.generate(row.example);
      await File('${outDir.path}/$base.wav').writeAsBytes(result.wavData());
      // manifest 的键与音标库那套一致：归一化符号（去斜杠、ɡ→g）
      fragment.add({
        'phoneme': row.phoneme.replaceAll('/', ''),
        'word': row.example,
        'file': '$base.mp3',
      });
      debugPrint('[gen] ${row.phoneme} → $base.wav（${row.example}）');
    }
    await File('${outDir.path}/manifest-fragment.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(fragment),
    );
    await engine.dispose();

    // 停一会儿等 `adb pull`：测试一结束应用就被卸载，外部文件目录随之消失，
    // 所以拉取必须在测试还活着的时候完成（轮询该目录出现后立即 pull）。
    debugPrint('[gen] 产出目录：${outDir.path}（等 30s 供 adb pull）');
    await Future<void>.delayed(const Duration(seconds: 30));
    debugPrint('[gen] 等待结束');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
