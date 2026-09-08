# Contexta Flutter App

Contexta 英语学习 App（Flutter）。服务端 API（投放同步 / 远程查词 / 手机号登录）见
[`impl/server`](../server/README.md)。

## 构建

服务端地址经编译期常量 `AppConfig.serverBaseUrl`（`String.fromEnvironment('SERVER_BASE_URL')`）
注入，两种方式（同名 key 时命令行优先）：

- **`android/local.properties`**（推荐，gitignore 不入库）：
  ```properties
  server.baseUrl=http://47.112.20.32:443
  ```
  Gradle 打包时自动以 `--dart-define` 语义注入（见 `android/app/build.gradle.kts`）。
- **命令行**（可覆盖 local.properties）：
  ```sh
  flutter build apk --debug --dart-define=SERVER_BASE_URL=http://47.112.20.32:443
  ```

不注入时 `serverBaseUrl` 为空字符串，所有服务端调用将失败——构建前请务必配置。

## 文档

- `ACCEPTANCE.md` — 真机验收清单（迁移期，部分条目已过时）
- `docs/` — 主题文档（数据库 schema、查词、TTS 等）
