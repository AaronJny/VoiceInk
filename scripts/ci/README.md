# 私有 macOS 构建

`macos-build.yml` 在 `main`、`upgrade/**`、`ci/cloud-baseline` 推送和手动触发时构建；PR 仅进行无私钥编译和聚焦测试，不生成正式签名产物。构建与签名分为两个 job；Secrets 只在测试成功后的签名 job 的签名步骤注入。该工作流用于受信的本仓代码，不应启用 `pull_request_target` 或将签名授权给外部贡献者分支。

- `ci/cloud-baseline`：现有 2.11 定制版，Debug + 原有锁定依赖。
- `upgrade/**` / `main`：2.27，Release + 2.27 锁定依赖。
- 两者均须产生生产 `VoiceInk.app` / `com.prakashjoshipax.VoiceInk`，不是 `VoiceInk Dev.app`。
- ARM64 runner `macos-26`，固定 `/Applications/Xcode_26.6.app`，记录实际 ImageVersion 并断言 Swift >= 6.3。GitHub hosted OS 镜像会滚动更新，并非固定 VM 快照。
- 官方 Whisper v1.9.2 XCFramework 的 SHA-256 固定为 `af74fed13ea7f2d5ca2a39d9f58ec177713fafd7cab63aef4e27b79f3ceca80b`。版本与 digest 源自官方 release API，不依赖本机已有框架。
- 构建/测试使用 `LOCAL_BUILD`，不接入 CloudKit。CI 不上传用户数据、真实音频或 ASR 模型，且不运行无输入会空通过的 `ASRBenchmarkTests`。
- 现有 Secret：`SIGNING_CERTIFICATE_P12_BASE64`、`SIGNING_CERTIFICATE_PASSWORD`；变量 `SIGNING_IDENTITY_SHA1` 必须与交接原身份完全一致。
- 临时钥匙串仅在签名步骤存在。先核对原证书 SHA-1/SHA-256，私钥留在临时钥匙串；仅在一次性 runner 中授予原证书 codeSign 用途信任。签名后删除私钥钥匙串和公有证书、恢复搜索列表，剩余信任记录随 GitHub 托管一次性环境销毁；元数据记录实际方式，不声称手工删除信任记录。不修改用户 Mac，不创建替代证书，不回退 ad-hoc。签名使用标准 `macos-15-intel` 池，仍严格验证输入产物为 ARM64；编译继续使用 Xcode 26.6 ARM64。
- build 成功后将测试前的干净 app 以 ditto 封为 `UNSIGNED-VoiceInk-arm64.zip` 中间工件，明确不可直接安装，保留 3 天。附源码 commit、run ID、构建配置、工具链、测试摘要及 SHA-256。sign 仅下载同一 run 工件，校验后签名。失败时仅重跑 sign job，无需重复全量编译；中间工件过期后需重跑 build。
- 在测试前暂存干净 app，不把测试注入的 .xctest 交付给用户。从内向外签名、逐个可执行文件核对证书指纹，并验证主包 entitlements、生产 ID 与 designated requirement。zip 使用 `ditto`，解压后重做签名核验。
- 应用工件包含 zip、`build-info.json` 与工具链信息。日志和 xcresult 在独立诊断工件中，保留 7 天；应用保留 14 天。

云端通过不等于实机升级验收。安装前备份旧 app 和一致性用户数据，在 M1 Pro 上验证权限、录音、粘贴、OCR、转录、润色和原配置/统计，见根目录 HANDOFF.md。

核实来源（2026-11-12）：
- https://github.com/actions/runner-images/blob/main/README.md
- https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md
- https://api.github.com/repos/ggml-org/whisper.cpp/releases/tags/v1.9.2

- https://api.github.com/repos/actions/download-artifact/git/ref/tags/v4.3.0

## 构建缓存与耗时

仅缓存 `.ci-build/SourcePackages`、`Build/Intermediates.noindex`、`Build/Products` 和 `ModuleCache.noindex`。编译缓存仅在编译成功后、测试注入前保存（v2 key）；暂存前强制检查无 XCTest。缓存中的 app 仅为编译阶段 ad-hoc 产物，签名在另一 job 的临时目录进行，不会写回缓存。不缓存测试结果、原证书签名产物、签名钥匙串、P12、私钥、临时信任或用户数据。恢复缓存后仍执行编译和全部八组测试，不能以缓存成功替代测试通过。

SPM key 按实际 runner 架构、Xcode/Swift/SDK 和 Package.resolved 隔离；编译 key 另含配置、xcconfig、项目、entitlements、构建脚本及含 Whisper 摘要的准备脚本。保存 key 追加源码 commit，只在相同依赖/工具链前缀恢复；Xcode仍自行判定源码增量，所有构建继续锁定依赖。PR只恢复、不保存，只有受信本仓 push 可以保存。

工作流单独显示生产 app 编译与八组测试。`cache-status.json` 记录精确/前缀命中，`stage-timings.json` 和 job summary 记录实际阶段耗时。warm-restored 只代表缓存已恢复，不承诺全部目标免编译；冷/热收益必须比较实际运行。官方 cache v4.2.3 commit 已核验： https://api.github.com/repos/actions/cache/git/ref/tags/v4.2.3

实测冷构建（2026-11-12，c6e012）：3 CPU / 7 GiB，Release 编译 908 秒，49 项测试 49 秒；两层缓存均成功保存。未单独追加热构建测量。


## DMG 与发布（personal.2 起）

正式构建现在自动执行 build → sign → dmg。DMG job 只读取同一运行的已签名包，不接触私钥；校验源码、测试摘要哈希、证书、只读挂载与应用完整清单，产出 `VoiceInk-DMG-<commit>`。

发布是明确的独立操作，不是每次 main 推送自动发布。为已在 main 上完成成功构建的提交创建 `release/v2.27-personal.N` 分支，或在 main 手动运行 Release verified VoiceInk DMG 并填入新 tag。发布脚本只接受同一源码的成功正式构建，不会使用另一个“最新成功”的提交，且不覆盖已存在的 Release。下载公开于仓库权限范围内的发布资产后再次核对 SHA256 和 tag。

2026-11-13 用户批准合并有用工作到 main 并删除过程分支。此次合并保留以下过程头为祖先：`ac3cd5623f1bc71e1f334bf47d03d5e0131f4faf`（签名探针及旧基线）、`98f828cfc0f26e7bab7ca74e448fccbf2fe975ba`（上游导入）、`9055c81a15a9019959ea4fdb86c78e0973569cc8`（旧包重签）、`4138bf73075566234e1992eae9c1f851324f0f91`（首次 DMG 与发布）。仅保留有用的正式流程在当前源码；实验脚本仍可从提交历史恢复。`cleanup-process-branches.py` 仅删除本次审计列明、头未改变且已在 main 历史中的分支，不清理其他新分支。
