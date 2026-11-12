# 私有 macOS 构建

`macos-build.yml` 在 `main`、`upgrade/**`、`ci/cloud-baseline` 推送和手动触发时构建；PR 仅进行无私钥编译和聚焦测试，不生成正式签名产物。构建 Secrets 只在测试成功后的签名步骤注入。该工作流用于受信的本仓代码，不应启用 `pull_request_target` 或将签名授权给外部贡献者分支。

- `ci/cloud-baseline`：现有 2.11 定制版，Debug + 原有锁定依赖。
- `upgrade/**` / `main`：2.27，Release + 2.27 锁定依赖。
- 两者均须产生生产 `VoiceInk.app` / `com.prakashjoshipax.VoiceInk`，不是 `VoiceInk Dev.app`。
- ARM64 runner `macos-26`，固定 `/Applications/Xcode_26.6.app`，记录实际 ImageVersion 并断言 Swift >= 6.3。GitHub hosted OS 镜像会滚动更新，并非固定 VM 快照。
- 官方 Whisper v1.9.2 XCFramework 的 SHA-256 固定为 `af74fed13ea7f2d5ca2a39d9f58ec177713fafd7cab63aef4e27b79f3ceca80b`。版本与 digest 源自官方 release API，不依赖本机已有框架。
- 构建/测试使用 `LOCAL_BUILD`，不接入 CloudKit。CI 不上传用户数据、真实音频或 ASR 模型，且不运行无输入会空通过的 `ASRBenchmarkTests`。
- 现有 Secret：`SIGNING_CERTIFICATE_P12_BASE64`、`SIGNING_CERTIFICATE_PASSWORD`；变量 `SIGNING_IDENTITY_SHA1` 必须与交接原身份完全一致。
- 临时钥匙串仅在签名步骤存在，退出及 always 清理都删除；不创建替代证书，不自动回退 ad-hoc，不更改系统信任。若全新 runner 不认可原自签名证书，步骤明确失败，需要单独处理信任，而非静默换证书。
- 从内向外签名、逐个可执行文件核对证书指纹，并验证主包 entitlements、生产 ID 与 designated requirement。zip 使用 `ditto`，解压后重做签名核验。
- 应用工件包含 zip、`build-info.json` 与工具链信息。日志和 xcresult 在独立诊断工件中，保留 7 天；应用保留 14 天。

云端通过不等于实机升级验收。安装前备份旧 app 和一致性用户数据，在 M1 Pro 上验证权限、录音、粘贴、OCR、转录、润色和原配置/统计，见根目录 HANDOFF.md。

核实来源（2026-11-12）：
- https://github.com/actions/runner-images/blob/main/README.md
- https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md
- https://api.github.com/repos/ggml-org/whisper.cpp/releases/tags/v1.9.2
