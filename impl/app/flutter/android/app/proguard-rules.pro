# flutter_onnxruntime 未带 consumer rules：R8 混淆 ai.onnxruntime 的 JNI 类
# 会导致 OrtSession.run 原生方法绑定失效 → SIGABRT 崩溃（release 包点播放即退出）。
# 保留 onnxruntime 全部公开类（JNI 通过 native method 名绑定，不能混淆）。
-keep class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**
