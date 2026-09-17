# Contexta Flutter App

Contexta 英语学习 App（Flutter）。服务端 API（投放同步 / 远程查词 / 手机号登录）见
[`impl/server`](../server/README.md)。

## 构建

服务端地址经编译期常量 `AppConfig.serverBaseUrl`（`String.fromEnvironment('SERVER_BASE_URL')`）
注入，两种方式（同名 key 时命令行优先）：

- **`android/local.properties`**（推荐，gitignore 不入库）：
  ```properties
  server.baseUrl=https://47.112.20.32
  ```
  Gradle 打包时自动以 `--dart-define` 语义注入（见 `android/app/build.gradle.kts`）。
- **命令行**（可覆盖 local.properties）：
  ```sh
  flutter build apk --debug --dart-define=SERVER_BASE_URL=https://47.112.20.32
  ```

### 自签名 HTTPS（生产 = 固定 IP + 自签名证书）

生产 `https://47.112.20.32` 用自签名证书（无域名，CA 不签发 IP 证书）。App 侧的信任来自
**内嵌证书**：`assets/certs/server.crt` 启动时经 `rootBundle` 预载（`lib/main.dart`），
注入 Dart `SecurityContext`（`lib/di/providers.dart`，只信任该证书）。

> ⚠️ **为什么不用 Android network security config**：Dart 的 TLS 栈（BoringSSL）不读 NSC，
> 只会报 `CERTIFICATE_VERIFY_FAILED: self signed certificate`（2026-09-17 真机实测）。
> 证书必须经 Dart 侧注入；debug 模式下 asset 不在文件系统里，必须走 `rootBundle`。

> ⚠️ **纪律**：`assets/certs/server.crt` 必须与服务器 `/opt/contexta/server/certs/server.crt`
> 是同一份证书。**换 IP 或重签证书后必须同步替换该文件并重新打包**，否则已装 App 握手即断。
> 全链路（生成 → 推服务器 → 更新 App）见 `impl/server/docs/config-and-deploy.md` §2.1。

不注入时 `serverBaseUrl` 为空字符串，所有服务端调用将失败——构建前请务必配置。

## 文档

- `ACCEPTANCE.md` — 真机验收清单（迁移期，部分条目已过时）
- `docs/` — 主题文档（数据库 schema、查词、TTS 等）
