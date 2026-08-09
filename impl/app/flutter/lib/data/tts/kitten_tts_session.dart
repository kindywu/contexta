import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:kittentts/kittentts_flutter.dart' as kit;

import 'tts_cache_manager.dart';

/// KittenTTS 会话抽象：由 [KittenTtsFactory] 创建，测试注入 fake。
///
/// 职责：生成 WAV → audioplayers 播放 → 完成时回调 utterance id。
/// 每次 speak 打断上一次（生成 Job 取消 + 播放器 stop）。
abstract interface class KittenTtsSession {
  /// 生成并播放 [text]，结束后调用 finishListener。
  Future<void> speak(String text, {required double speed, required String utteranceId});

  /// 按段落生成 + 播放（全文朗读首次路径）。
  ///
  /// 逐段 [kit.KittenTTS.generate] → 写缓存 → 播放；每段完成上报进度
  /// (done=已完成段落数, total=总段落数)。全部播完调用 finishListener。
  Future<void> speakParagraphs(
    List<String> texts, {
    required List<int> paragraphIds,
    required double speed,
    required String utteranceId,
  });

  /// 全文朗读：标题 + 正文段落，单个 utterance 内无缝衔接播放。
  ///
  /// 双 worker 流水线：生成 worker 把每段 WAV 推入待播队列（缓存命中直接
  /// 推文件路径，未命中生成 + 写缓存），播放 worker 按序消费播放——播放
  /// 等待生成，生成无需等待，按段落依次执行。[title] 可为空跳过。
  /// 进度只计正文段落（done/total）；全部播完调用 finishListener。
  Future<void> speakFullArticle({
    String? title,
    required List<({int id, String text})> paragraphs,
    required double speed,
    required String utteranceId,
  });

  /// 播放本地 WAV 文件路径（缓存命中时）。
  /// 返回 true 表示文件存在并开始播放，false 表示文件不存在。
  Future<bool> playFile(String filePath, {required String utteranceId});

  /// 顺序播放多个本地 WAV 文件，完成后调用 finishListener。
  /// 每个文件播完自动切到下一个。
  Future<void> playFiles(List<String> filePaths, {required String utteranceId});

  /// 停止当前生成/播放（触发 finishListener）。
  Future<void> stop();

  /// 注册播放完成回调（自然结束 / stop / 被新 utterance 打断）。
  void setFinishListener(void Function(String utteranceId)? listener);

  /// 注册生成进度回调（已生成句子数 / 总句子数），长文本流式生成时上报。
  void setProgressListener(
      void Function(String utteranceId, int done, int total)? listener);

  /// 注册「段落开始播放」回调（播放 worker 每段实际发声前调用）。
  /// 带 utterance id、段落索引（正文从 0 起，标题段不上报）与正文总段数；
  /// 传 null 注销。与 [setProgressListener]（生成进度）不同，此回调反映真实播放位置。
  void setOnParagraphStarted(
      void Function(String utteranceId, int paragraphIndex, int total)? listener);

  /// 后台预生成段落音频并写入缓存（跳过已缓存段落）。
  ///
  /// 引擎空闲时调用（播放结束后），不抢占播放。被 stop/新播放打断。
  Future<void> pregenerateParagraphs({
    required List<({int paragraphId, String text})> paragraphs,
    required double speed,
  });

  Future<void> dispose();
}

/// KittenTTS 插件工厂（`KittenTTS.create` 的可注入包装）。
typedef KittenTtsFactory = Future<KittenTtsSession> Function({
  required String onnxPath,
  required String voicesPath,
});

/// 生产实现：KittenTTS 插件 + audioplayers 播放 + 本地文件缓存。
class KittenTtsPluginSession implements KittenTtsSession {
  KittenTtsPluginSession({
    required this._engine,
    required this._player,
    this.cache,
  });

  static const int _streamThreshold = 100; // 超过此字符数用流式

  final kit.KittenTTS _engine;
  final AudioPlayer _player;
  final TtsCacheManager? cache;
  void Function(String utteranceId)? _finishListener;
  void Function(String utteranceId, int done, int total)? _progressListener;
  void Function(String utteranceId, int paragraphIndex, int total)?
      _paragraphStartedListener;
  String? _currentUtteranceId;
  Completer<void>? _playbackCompleter;
  StreamSubscription<void>? _completeSub;
  StreamSubscription<kit.KittenTTSResult>? _streamSub;
  final _generationJobs = <Future<void>>[];

  /// 工厂实现：用内置 phonemizer 数据创建 KittenTTS。
  static Future<KittenTtsSession> create({
    required String onnxPath,
    required String voicesPath,
  }) async {
    final instance = await kit.KittenTTS.create(
      config: kit.KittenTTSConfig(
        model: kit.model.micro,
        defaultVoice: kit.voice.bella,
        modelFiles: kit.KittenTTSModelFiles(
          onnxPath: onnxPath,
          voicesPath: voicesPath,
        ),
        phonemizer: kit.CEPhonemizer(allowRuleBasedFallback: true),
        analytics: false,
      ),
    );
    final player = AudioPlayer();
    await player.setReleaseMode(ReleaseMode.stop);
    return KittenTtsPluginSession(engine: instance, player: player);
  }

  @override
  Future<void> speak(
    String text, {
    required double speed,
    required String utteranceId,
  }) async {
    debugPrint('[KittenTTS] speak: len=${text.length} speed=$speed id=$utteranceId');
    await _stopCurrent();
    _currentUtteranceId = utteranceId;
    final job = _generateAndPlay(text, speed, utteranceId);
    _generationJobs.add(job);
    try {
      await job;
    } finally {
      _generationJobs.remove(job);
    }
  }

  @override
  Future<bool> playFile(
    String filePath, {
    required String utteranceId,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) return false;

    debugPrint('[KittenTTS] playFile: $filePath id=$utteranceId');
    await _stopCurrent();
    _currentUtteranceId = utteranceId;

    final task = _playFileAsync(filePath, utteranceId);
    _generationJobs.add(task);
    try {
      await task;
    } finally {
      _generationJobs.remove(task);
    }
    return true;
  }

  @override
  Future<void> speakParagraphs(
    List<String> texts, {
    required List<int> paragraphIds,
    required double speed,
    required String utteranceId,
  }) async {
    debugPrint('[KittenTTS] speakParagraphs: ${texts.length} paragraphs id=$utteranceId');
    await _stopCurrent();
    _currentUtteranceId = utteranceId;

    final task = _speakParagraphsSequential(texts, paragraphIds, speed, utteranceId);
    _generationJobs.add(task);
    try {
      await task;
    } finally {
      _generationJobs.remove(task);
    }
  }

  /// 逐段：查缓存 → 命中播文件 / 未命中生成+写缓存+播放；每段完成上报进度。
  ///
  /// 流水线：段落 i 播放期间，后台并发预取段落 i+1..i+3（引擎空闲），
  /// 播放到后续段落时缓存已就绪，几乎无等待。
  Future<void> _speakParagraphsSequential(
    List<String> texts,
    List<int> paragraphIds,
    double speed,
    String utteranceId,
  ) async {
    final total = texts.length;
    final progressListener = _progressListener;
    Future<void>? prefetch;
    try {
      for (var i = 0; i < total; i++) {
        if (_currentUtteranceId != utteranceId) return;

        final cm = cache;
        String? cachedPath;
        if (cm != null && paragraphIds[i] > 0) {
          cachedPath = await cm.lookupParagraph(paragraphIds[i], speed);
        }

        if (cachedPath != null) {
          // 缓存命中（预取已完成该段）：直接播文件，引擎空闲可并行预取
          if (prefetch == null) {
            prefetch = _prefetchRemaining(
              texts, paragraphIds, speed, utteranceId,
              startIndex: i + 2,
            );
          }
          debugPrint('[KittenTTS] paragraph ${i + 1}/$total: cache HIT, play file');
          await _playFileSource(File(cachedPath).openRead(), utteranceId);
        } else {
          debugPrint('[KittenTTS] paragraph ${i + 1}/$total: gen+play');
          final result = await _engine.generate(texts[i], speed: speed);
          if (_currentUtteranceId != utteranceId) return;

          final wav = result.wavData();

          // 写缓存（段落级，FIFO 淘汰）
          if (cm != null && paragraphIds[i] > 0) {
            try {
              await cm.writeParagraph(
                paragraphId: paragraphIds[i],
                speed: speed,
                wavData: wav,
              );
            } catch (e) {
              debugPrint('[KittenTTS] cache write FAILED: $e');
            }
          }

          // 当前段已生成，引擎空闲 → 启动后续段落预取（i+2 起，i+1 由循环处理）
          if (prefetch == null) {
            prefetch = _prefetchRemaining(
              texts, paragraphIds, speed, utteranceId,
              startIndex: i + 2,
            );
          }

          // 播放该段（await 播完再处理下一段）
          await _playWav(wav, utteranceId);
        }

        if (progressListener != null) {
          debugPrint('[KittenTTS] progress: ${i + 1}/$total');
          progressListener(utteranceId, i + 1, total);
        }
      }
      // 全部播完：立即通知完成（预取在后台自然收尾，不阻塞 UI 状态复位）
      if (_currentUtteranceId == utteranceId) {
        _currentUtteranceId = null;
        _finishListener?.call(utteranceId);
      }
      // 让预取继续跑完（fire-and-forget；stop/新播放时其内部检查退出）
    } catch (e) {
      debugPrint('[KittenTTS] speakParagraphs ERROR: $e');
      if (_currentUtteranceId == utteranceId) {
        _currentUtteranceId = null;
        _finishListener?.call(utteranceId);
      }
    }
  }

  /// 全文朗读：标题 + 正文段落，单个 utterance 内无缝衔接播放。
  ///
  /// 双 worker 流水线（对照需求：一个线程生成、一个线程播放，播放等待
  /// 生成，生成无需等待，按段落依次执行）：
  /// - 生成 worker：逐段查缓存 → 命中推文件路径 / 未命中生成 + 写缓存后推
  ///   WAV；标题在最前。用 [StreamController] 推送，播放侧顺序消费。
  /// - 播放 worker：依次播放队列项；标题播完立即衔接段落，无缝隙。
  /// - 进度只计正文段落 (done/total)；全部播完调用 finishListener。
  @override
  Future<void> speakFullArticle({
    String? title,
    required List<({int id, String text})> paragraphs,
    required double speed,
    required String utteranceId,
  }) async {
    debugPrint('[KittenTTS] speakFullArticle: title="${title ?? ""}" paras=${paragraphs.length} id=$utteranceId');
    await _stopCurrent();
    _currentUtteranceId = utteranceId;

    final controller = StreamController<_QueuedAudio>.broadcast();
    final generationDone = Completer<void>();

    // 播放 worker：顺序消费队列，播完自动切换下一项（标题→段落无缝）
    final playback = _playQueued(controller.stream, utteranceId, generationDone);

    // 生成 worker：标题 → 逐段（查缓存/生成+写缓存），推入队列
    final generation = _generateFullArticle(
      controller: controller,
      title: title,
      paragraphs: paragraphs,
      speed: speed,
      utteranceId: utteranceId,
    );
    generationDone.complete(generation);
    // 生成 worker 推完全部后关闭流（播放 worker 播完最后一项结束）
    await generation;
    await controller.close();
    await playback;

    if (_currentUtteranceId == utteranceId) {
      _currentUtteranceId = null;
      _finishListener?.call(utteranceId);
    }
  }

  /// 生成 worker：标题 + 逐段音频推入待播队列。
  Future<void> _generateFullArticle({
    required StreamController<_QueuedAudio> controller,
    required String? title,
    required List<({int id, String text})> paragraphs,
    required double speed,
    required String utteranceId,
  }) async {
    final cm = cache;
    try {
      if (title != null && title.isNotEmpty) {
        if (_currentUtteranceId != utteranceId) return;
        debugPrint('[KittenTTS] fullArticle: generating title');
        final result = await _engine.generate(title, speed: speed);
        if (_currentUtteranceId != utteranceId) return;
        controller.add(_QueuedAudio.wav(result.wavData(), isTitle: true));
      }

      final total = paragraphs.length;
      final progressListener = _progressListener;
      for (var i = 0; i < total; i++) {
        if (_currentUtteranceId != utteranceId) return;
        final para = paragraphs[i];

        String? cachedPath;
        if (cm != null && para.id > 0) {
          cachedPath = await cm.lookupParagraph(para.id, speed);
        }

        if (cachedPath != null) {
          debugPrint('[KittenTTS] fullArticle: para ${i + 1}/$total cache HIT');
          controller.add(_QueuedAudio.file(cachedPath));
        } else {
          debugPrint('[KittenTTS] fullArticle: para ${i + 1}/$total gen');
          final result = await _engine.generate(para.text, speed: speed);
          if (_currentUtteranceId != utteranceId) return;

          final wav = result.wavData();
          if (cm != null && para.id > 0) {
            try {
              await cm.writeParagraph(
                paragraphId: para.id,
                speed: speed,
                wavData: wav,
              );
            } catch (e) {
              debugPrint('[KittenTTS] fullArticle cache write FAILED: $e');
            }
          }
          controller.add(_QueuedAudio.wav(wav));
        }

        // 进度：已推入播放队列的段落数 / 总段落数（标题不计入）
        if (progressListener != null) {
          debugPrint('[KittenTTS] fullArticle progress: ${i + 1}/$total');
          progressListener(utteranceId, i + 1, total);
        }
      }
      debugPrint('[KittenTTS] fullArticle: generation done');
    } catch (e) {
      debugPrint('[KittenTTS] fullArticle generate ERROR: $e');
    } finally {
      await controller.close();
    }
  }

  /// 播放 worker：依次播放 [items]；全部播完（或被打断）完成 [done]。
  Future<void> _playQueued(
    Stream<_QueuedAudio> items,
    String utteranceId,
    Completer<void> done,
  ) async {
    try {
      await for (final item in items) {
        if (_currentUtteranceId != utteranceId) return;
        debugPrint('[KittenTTS] fullArticle play: ${item.isTitle ? "title" : "para"}');
        if (item.bytes != null) {
          await _playWav(item.bytes!, utteranceId);
        } else if (item.filePath != null) {
          final file = File(item.filePath!);
          if (await file.exists()) {
            await _playFileSource(file.openRead(), utteranceId);
          }
        }
      }
      debugPrint('[KittenTTS] fullArticle: playback done');
    } finally {
      if (!done.isCompleted) done.complete();
    }
  }

  /// 后台并发预取段落 [startIndex..end]，跳过已缓存；播放期间引擎空闲，
  /// 用 native 串行锁排队生成，写完缓存即可。被 stop/新 utterance 打断。
  Future<void> _prefetchRemaining(
    List<String> texts,
    List<int> paragraphIds,
    double speed,
    String utteranceId,
    {required int startIndex,
    int batchSize = 3,
    }) async {
    final cm = cache;
    if (cm == null) return;

    // 覆盖全部剩余段落（无窗口限制，保证最后一段也预取）
    final end = texts.length;
    if (startIndex >= end) return;

    debugPrint('[KittenTTS] prefetch: paragraphs [$startIndex, $end)');

    // 过滤掉已缓存的（避免重复生成）
    final toGen = <int>[];
    for (var i = startIndex; i < end; i++) {
      if (paragraphIds[i] > 0) {
        final needs = await cm.needsGenerate(paragraphIds[i], speed);
        if (needs) toGen.add(i);
      }
    }
    if (toGen.isEmpty) return;

    // 分批并发（native 锁串行排队，Dart 层重叠），每批 3 个
    for (var b = 0; b < toGen.length; b += batchSize) {
      if (_currentUtteranceId != utteranceId) return;
      final batch = toGen.sublist(
        b,
        b + batchSize > toGen.length ? toGen.length : b + batchSize,
      );
      await Future.wait(batch.map((i) async {
        if (_currentUtteranceId != utteranceId) return;
        try {
          final result = await _engine.generate(texts[i], speed: speed);
          if (_currentUtteranceId != utteranceId) return;
          await cm.writeParagraph(
            paragraphId: paragraphIds[i],
            speed: speed,
            wavData: result.wavData(),
          );
          debugPrint('[KittenTTS] prefetch: paragraph ${paragraphIds[i]} OK');
        } catch (e) {
          debugPrint('[KittenTTS] prefetch: paragraph ${paragraphIds[i]} FAILED: $e');
        }
      }));
    }
  }

  @override
  Future<void> playFiles(
    List<String> filePaths, {
    required String utteranceId,
  }) async {
    debugPrint('[KittenTTS] playFiles: ${filePaths.length} files id=$utteranceId');
    await _stopCurrent();
    _currentUtteranceId = utteranceId;

    final task = _playFilesSequential(filePaths, utteranceId);
    _generationJobs.add(task);
    try {
      await task;
    } finally {
      _generationJobs.remove(task);
    }
  }

  /// 顺序播放多个 WAV 文件，每个文件播完检查 utterance 是否有效。
  Future<void> _playFilesSequential(List<String> filePaths, String utteranceId) async {
    try {
      for (int i = 0; i < filePaths.length; i++) {
        if (_currentUtteranceId != utteranceId) return;
        final file = File(filePaths[i]);
        if (!await file.exists()) {
          debugPrint('[KittenTTS] playFiles: missing ${filePaths[i]}, skip');
          continue;
        }
        debugPrint('[KittenTTS] playFiles: [${i + 1}/${filePaths.length}] ${filePaths[i]}');
        await _playFileSource(file.openRead(), utteranceId);
      }
      if (_currentUtteranceId == utteranceId) {
        _currentUtteranceId = null;
        _finishListener?.call(utteranceId);
      }
    } catch (e) {
      debugPrint('[KittenTTS] playFiles ERROR: $e');
      if (_currentUtteranceId == utteranceId) {
        _currentUtteranceId = null;
        _finishListener?.call(utteranceId);
      }
    }
  }

  Future<void> _playFileAsync(String filePath, String utteranceId) async {
    try {
      await _playFileSource(File(filePath).openRead(), utteranceId);
      if (_currentUtteranceId == utteranceId) {
        _currentUtteranceId = null;
        _finishListener?.call(utteranceId);
      }
    } catch (e) {
      debugPrint('[KittenTTS] playFile ERROR: $e');
      if (_currentUtteranceId == utteranceId) {
        _currentUtteranceId = null;
        _finishListener?.call(utteranceId);
      }
    }
  }

  Future<void> _playFileSource(Stream<List<int>> stream, String utteranceId) async {
    _playbackCompleter = Completer<void>();
    _completeSub?.cancel();
    _completeSub = _player.onPlayerComplete.listen((_) => _finishPlayback());
    await _player.play(BytesSource(
      await stream.toList().then((chunks) {
        final total = chunks.fold<int>(0, (sum, c) => sum + c.length);
        final bytes = Uint8List(total);
        var offset = 0;
        for (final chunk in chunks) {
          bytes.setAll(offset, chunk);
          offset += chunk.length;
        }
        return bytes;
      }),
      mimeType: 'audio/wav',
    ));
    await _playbackCompleter!.future;
  }

  // ─── 生成 + 播放 ────────────────────────────────────────────────

  Future<void> _generateAndPlay(
    String text,
    double speed,
    String utteranceId,
  ) async {
    try {
      if (text.length > _streamThreshold) {
        await _generateAndPlayStream(text, speed, utteranceId);
      } else {
        await _generateAndPlaySingle(text, speed, utteranceId);
      }
    } catch (e) {
      debugPrint('[KittenTTS] generate ERROR: $e');
      if (_currentUtteranceId == utteranceId) {
        _currentUtteranceId = null;
        _finishListener?.call(utteranceId);
      }
    }
  }

  Future<void> _generateAndPlaySingle(
    String text,
    double speed,
    String utteranceId,
  ) async {
    debugPrint('[KittenTTS] generating (single): len=${text.length} speed=$speed');
    final result = await _engine.generate(text, speed: speed);
    debugPrint('[KittenTTS] generated OK, wavSize=${result.wavData().length}');
    if (_currentUtteranceId != utteranceId) return;
    await _playWav(result.wavData(), utteranceId);
    // 成功播完 → 通知完成（stop/打断时由 _stopCurrent 触发，此处只补成功路径）
    if (_currentUtteranceId == utteranceId) {
      _currentUtteranceId = null;
      _finishListener?.call(utteranceId);
    }
  }

  /// 长文本流式生成 + 播放。
  Future<void> _generateAndPlayStream(
    String text,
    double speed,
    String utteranceId,
  ) async {
    debugPrint('[KittenTTS] generating (stream): len=${text.length} speed=$speed');
    final stream = _engine.stream(text, speed: speed);
    _streamSub?.cancel();

    // 进度：插件按 ~200 字符 chunk yield，无法预知总数；用累计块数上报，
    // 播放条显示已生成块数（如「生成中 2 段」）
    var doneChunks = 0;
    final progressListener = _progressListener;
    debugPrint('[KittenTTS] stream progressListener=${progressListener != null}');

    final firstGenerated = Completer<void>();
    Completer<void>? lastPlayed;

    _streamSub = stream.listen(
      (result) async {
        if (_currentUtteranceId != utteranceId) return;
        final wav = result.wavData();

        doneChunks++;
        if (progressListener != null) {
          debugPrint('[KittenTTS] progress: chunk $doneChunks');
          progressListener(utteranceId, doneChunks, -1);
        }

        final prev = lastPlayed;
        final thisDone = Completer<void>();
        lastPlayed = thisDone;

        if (prev != null) await prev.future;
        if (_currentUtteranceId != utteranceId) return;

        if (!firstGenerated.isCompleted) firstGenerated.complete();
        await _playWav(wav, utteranceId);
        thisDone.complete();
      },
      onError: (e) {
        debugPrint('[KittenTTS] stream ERROR: $e');
        if (!firstGenerated.isCompleted) firstGenerated.completeError(e);
      },
      onDone: () async {
        debugPrint('[KittenTTS] stream generation done, waiting for playback...');
        if (!firstGenerated.isCompleted) firstGenerated.complete();
        final last = lastPlayed;
        if (last != null) await last.future;
        if (_currentUtteranceId == utteranceId) {
          _currentUtteranceId = null;
          _finishListener?.call(utteranceId);
        }
      },
      cancelOnError: false,
    );

    try {
      await firstGenerated.future;
    } catch (e) {
      if (_currentUtteranceId == utteranceId) {
        _currentUtteranceId = null;
        _finishListener?.call(utteranceId);
      }
    }
  }

  Future<void> _playWav(Uint8List wav, String utteranceId) async {
    _playbackCompleter = Completer<void>();
    _completeSub?.cancel();
    _completeSub = _player.onPlayerComplete.listen((_) => _finishPlayback());
    try {
      await _player.play(BytesSource(wav, mimeType: 'audio/wav'));
      await _playbackCompleter!.future;
    } catch (_) {
      _finishPlayback();
      rethrow;
    }
  }

  void _finishPlayback() {
    final completer = _playbackCompleter;
    _playbackCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  @override
  Future<void> stop() async {
    await _stopCurrent();
  }

  Future<void> _stopCurrent() async {
    final id = _currentUtteranceId;
    _currentUtteranceId = null;
    _streamSub?.cancel();
    _streamSub = null;
    _finishPlayback();
    try {
      await _player.stop();
    } catch (_) {}
    if (id != null) {
      _finishListener?.call(id);
    }
  }

  @override
  void setFinishListener(void Function(String utteranceId)? listener) {
    _finishListener = listener;
  }

  @override
  void setProgressListener(
      void Function(String utteranceId, int done, int total)? listener) {
    _progressListener = listener;
  }

  @override
  void setOnParagraphStarted(
      void Function(String utteranceId, int paragraphIndex, int total)?
          listener) {
    _paragraphStartedListener = listener;
  }

  @override
  Future<void> pregenerateParagraphs({
    required List<({int paragraphId, String text})> paragraphs,
    required double speed,
  }) async {
    final cm = cache;
    if (cm == null) return;

    // 先筛出需要生成的段落（避免无谓并发）
    final toGenerate = <({int paragraphId, String text})>[];
    for (final p in paragraphs) {
      if (_currentUtteranceId != null) return; // 新播放打断预生成
      final needs = await cm.needsGenerate(p.paragraphId, speed);
      if (needs) toGenerate.add(p);
    }
    debugPrint('[KittenTTS] pregen: ${toGenerate.length}/${paragraphs.length} need generation');

    // 并发生成（限流：一次最多 3 段并发，避免内存峰值）
    for (var i = 0; i < toGenerate.length; i += 3) {
      if (_currentUtteranceId != null) return;
      final batch = toGenerate.sublist(
        i,
        i + 3 > toGenerate.length ? toGenerate.length : i + 3,
      );
      await Future.wait(batch.map((p) async {
        if (_currentUtteranceId != null) return;
        try {
          debugPrint('[KittenTTS] pregen: paragraph ${p.paragraphId} (batch ${i ~/ 3 + 1})');
          final result = await _engine.generate(p.text, speed: speed);
          if (_currentUtteranceId != null) return;
          final wav = result.wavData();
          await cm.writeParagraph(
            paragraphId: p.paragraphId,
            speed: speed,
            wavData: wav,
          );
          debugPrint('[KittenTTS] pregen: paragraph ${p.paragraphId} OK (${wav.length}B)');
        } catch (e) {
          debugPrint('[KittenTTS] pregen: paragraph ${p.paragraphId} FAILED: $e');
        }
      }));
    }
  }

  @override
  Future<void> dispose() async {
    await _streamSub?.cancel();
    await _completeSub?.cancel();
    await _engine.dispose();
    await _player.dispose();
  }
}

/// KittenTTS 语速映射：插件 speed 即实际语速（0.5–2.0）。
class KittenSpeedMapper {
  const KittenSpeedMapper();

  double actualRate(double displaySpeed) => displaySpeed.clamp(0.5, 2.0);
}

/// 全文朗读待播队列项：WAV 字节 或 缓存文件路径（二选一）。
class _QueuedAudio {
  _QueuedAudio.wav(Uint8List bytes, {this.isTitle = false})
      : bytes = bytes,
        filePath = null;

  _QueuedAudio.file(String path)
      : bytes = null,
        filePath = path,
        isTitle = false;

  final Uint8List? bytes;
  final String? filePath;
  final bool isTitle;
}
