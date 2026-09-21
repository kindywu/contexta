import 'dart:async';
import 'dart:convert';

import 'package:contexta/data/audio/asset_phoneme_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// `AssetPhonemeAudio` 的播放路径测试（平台侧用假 ClipPlayer）：
/// 录音库命中/未命中、播放启动失败、以及**平台不上报播放完成**。
///
/// 最后一条是回归测试：2026-09-20 真机上「音标点了却念出例词」——
/// 根因是等播完那一行 `.timeout(..., onTimeout: () {})` 类型不合法
/// （`onPlayerComplete` 是 `Stream<AudioEvent>`，onTimeout 必须返回 AudioEvent），
/// 运行时每次都抛，被 catch 成「播放失败」→ 再叠一层例词 TTS。
/// 修法：等播完失败只影响连读间隔，**不再把已启动的播放判成失败**。

/// 假播放器：记录调用；`complete` 控制播完事件是否上报；`failOnPlay` 模拟启动失败。
class _FakeClipPlayer implements ClipPlayer {
  _FakeClipPlayer({this.reportComplete = true, this.failOnPlay = false});

  final bool reportComplete;
  final bool failOnPlay;
  final List<String> played = [];
  int stopCount = 0;

  @override
  Future<void> play(String assetPath) async {
    if (failOnPlay) throw PlatformException(code: 'boom');
    played.add(assetPath);
  }

  @override
  Future<void> stop() async => stopCount++;

  /// 不上报时返回一个永不完成的 Future（模拟平台侧静默）。
  @override
  Future<void> get onComplete =>
      reportComplete ? Future.value() : Completer<void>().future;
}

AssetPhonemeAudio _audio(_FakeClipPlayer player) {
  final manifest = jsonEncode({
    'phonemes': [
      {'symbol': 'iː', 'normalized': 'iː', 'file': 's01.mp3', 'wordFile': 'w01.mp3'},
      // 没有 wordFile：例词那段回退 TTS
      {'symbol': 'ʊ', 'normalized': 'ʊ', 'file': 's09.mp3'},
      {'symbol': 'z', 'normalized': 'z', 'file': 's30.mp3', 'wordFile': 'w30.mp3'},
    ],
    // 字母读音行的例词：TTS 预生成，与音标库那套并列（/z/ 两边都有、内容不同）
    'letterWords': [
      {'phoneme': 'z', 'word': 'xylophone', 'file': 'l03.mp3'},
      {'phoneme': 'ks', 'word': 'box', 'file': 'l01.mp3'},
    ],
  });
  return AssetPhonemeAudio(
    bundle: _FakeBundle(manifest),
    player: player,
    // 超时按真实值走会在「不上报」用例里干等 5s，这里缩短
    manifestPath: 'manifest.json',
  );
}

/// 只实现 loadString 的 AssetBundle。
class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.content);

  final String content;

  @override
  Future<ByteData> load(String key) async => ByteData.view(Uint8List.fromList(utf8.encode(content)).buffer);

  @override
  Future<String> loadString(String key, {bool cache = true}) async => content;
}

void main() {
  test('命中录音库：调用播放器、返回 true', () async {
    final player = _FakeClipPlayer();
    final audio = _audio(player);
    expect(await audio.play('/ʊ/'), isTrue);
    expect(player.played, ['phonetics/s09.mp3']);
    expect(player.stopCount, 1);
  });

  test('例词录音：放的是 wordFile 那一段（与音标那段是两个文件）', () async {
    final player = _FakeClipPlayer();
    final audio = _audio(player);
    expect(await audio.playWord('/iː/'), isTrue);
    expect(player.played, ['phonetics/w01.mp3']);
  });

  test('清单里没有 wordFile：例词返回 false（调用方回退 TTS）', () async {
    final player = _FakeClipPlayer();
    expect(await _audio(player).playWord('/ʊ/'), isFalse);
    expect(player.played, isEmpty);
  });

  test('字母读音行的例词：走 letterWords 那批（同一个 /z/ 与音标库不串）', () async {
    final player = _FakeClipPlayer();
    final audio = _audio(player);

    expect(await audio.playLetterWord('/z/'), isTrue);
    expect(player.played, ['phonetics/l03.mp3'], reason: '放的是 xylophone，不是音标库的 zoo');

    expect(await audio.playWord('/z/'), isTrue);
    expect(player.played, ['phonetics/l03.mp3', 'phonetics/w30.mp3'],
        reason: '音标格的例词仍走音标库那套');
  });

  test('组合音只有例词录音：play / playWord 返回 false，playLetterWord 命中', () async {
    final player = _FakeClipPlayer();
    final audio = _audio(player);

    expect(await audio.play('/ks/'), isFalse);
    expect(await audio.playWord('/ks/'), isFalse);
    expect(await audio.playLetterWord('/ks/'), isTrue);
    expect(player.played, ['phonetics/l01.mp3']);
  });

  test('音标库里的例词不走 letterWords：/iː/ 返回 false', () async {
    final player = _FakeClipPlayer();
    expect(await _audio(player).playLetterWord('/iː/'), isFalse);
    expect(player.played, isEmpty);
  });

  test('符号不在库里：不播放、返回 false（调用方走例词兜底）', () async {
    final player = _FakeClipPlayer();
    final audio = _audio(player);
    expect(await audio.play('/zzz/'), isFalse);
    expect(await audio.playWord('/zzz/'), isFalse);
    expect(player.played, isEmpty);
  });

  test('播放启动失败：返回 false', () async {
    final player = _FakeClipPlayer(failOnPlay: true);
    expect(await _audio(player).play('/ʊ/'), isFalse);
  });

  test('平台不上报播放完成：仍算播放成功（回归：曾因此叠一层 TTS）', () async {
    final player = _FakeClipPlayer(reportComplete: false);
    final audio = _audio(player);
    // 超时前必须已经返回——这里用 fake_async 会跳到 5s，直接断言结果即可
    expect(await audio.play('/ʊ/').timeout(const Duration(seconds: 10)), isTrue);
    expect(player.played, ['phonetics/s09.mp3']);
  }, timeout: const Timeout(Duration(seconds: 15)));

  test('符号归一化：ɡ 与 g、斜杠差异都能命中', () async {
    final player = _FakeClipPlayer();
    expect(await _audio(player).play('iː'), isTrue);
    expect(await _audio(player).play('/iː/'), isTrue);
    expect(await _audio(player).play(' /iː/ '), isTrue);
  });

  test('manifest 缺失：全部按无录音处理（返回 false，不抛）', () async {
    final player = _FakeClipPlayer();
    final audio = AssetPhonemeAudio(
      bundle: _ThrowingBundle(),
      player: player,
    );
    expect(await audio.play('/ʊ/'), isFalse);
    expect(await audio.playWord('/ʊ/'), isFalse);
    expect(await audio.playLetterWord('/z/'), isFalse);
    expect(player.played, isEmpty);
  });
}

class _ThrowingBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => throw FlutterError('missing');

  @override
  Future<String> loadString(String key, {bool cache = true}) async => throw FlutterError('missing');
}
