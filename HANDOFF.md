# VoiceInk 定制版交接文档

更新时间：2026-11-12。面向接手本项目的 Codex 和维护者。

## 1. 接手目标与执行顺序

用户希望保留当前定制能力，将 VoiceInk 升级到较新的上游正式版本，改用 **GitHub Actions 的 macOS 环境构建，并尽量统一在云端签名**。

已完成：用户私有仓库 `AaronJny/VoiceInk` 已创建；定制代码及全部新增测试已提交为 `eb6ab17` 并推送至远端 `main`；原签名身份已导出并验证，签名 Secrets 与身份变量已配置。本文随文档提交保存。

接下来按以下顺序推进，每一步都留下可核查的结果：

1. 从新仓库 `main` 接手，保留已有定制基线及本文。
2. 打通最小 macOS 构建 workflow，确认工具链、依赖、Whisper XCFramework 和产物打包可重复。
3. 使用已有 Secrets 实现同一证书的云端签名，验证最终产物的身份和完整性。
4. 在升级分支整合已核实的上游 `v2.27`，逐项保留定制能力，运行聚焦回归。
5. 下载产物，在用户的 M1 Pro 上验证安装升级、权限、录音、粘贴、OCR、转录与润色。

尚未创建 Actions workflow、验证真实云端签名产物或执行 2.27 升级。若执行时出现更新的正式版，应重新评估差异，不自动跟随上游 `main`。

## 2. 当前项目与 Git 状态

| 项目 | 已核实状态 |
|---|---|
| 后续唯一工作目录 | `/Users/aaron/code/tools/VoiceInk` |
| 仓库结构 | 独立 Git 仓库，不再依赖旧 linked worktree 的 `.git` |
| 本机分支 | `planning/temp/20260819-sync-upstream-v211`，跟踪 `origin/main` |
| GitHub 默认分支 | `main` |
| 初次交接前 HEAD（历史锚点） | `bd781c9efa4bfcc6cffb38403d44ca613d2c7cd7` |
| 定制代码基线提交 | `eb6ab17b7bf74daab6c202cf5a5a08e8c9825b15`；最新 HEAD 以 `git log` 为准 |
| 当前代码的上游基线 | `304db118f655fd99612c4a833820ae927df73881`，2.11 后的一些修复 |
| 已获取的目标标签 | `v2.27` → `b5d1be9a7c7377dd059f37bb3e0f791b802d4001` |
| 当前 origin | `git@github.com:AaronJny/VoiceInk.git` |
| 官方 upstream | `https://github.com/Beingpax/VoiceInk.git` |
| 用户私有仓库 | `https://github.com/AaronJny/VoiceInk` |
| 定制代码与测试 | 已审查并提交，47 个文件；包含此前未跟踪的新增源文件和测试 |
| 安装版本 | `/Applications/VoiceInk.app`：2.11（211） |

迁移已经核对源文件内容、未提交 diff、暂存区 diff、全部 refs 和 Git 对象连通性；项目文件语法与新目录构建路径也已验证。原仓库保留为迁移备份，约 6 GB `.local-build` 缓存未复制。迁移本身没有重新构建应用。

原仓库是浅克隆，首次推送曾因缺少早期父提交而失败；已通过 `git fetch --unshallow upstream` 补齐，`git fsck --full` 通过，后续正常推送成功，没有强制推送或改写历史。

Codex 应从用户仓库的 `main` 接手。**不要直接切到这台 Mac 的旧本地 `main` 并将它当作当前定制版本。** 上游 `v2.27` 标签已在本机获取；新克隆需要比较时可从官方 `upstream` 获取该标签。

`planning/sessions/temp/20260819-sync-upstream-v211/session.md` 保留了早期过程记录，其中旧的阶段复选框不代表当前完成度；当前交接状态以本文和实际代码为准。

## 3. 用户要求与当前运行配置

### 3.1 必须遵守的要求

- 使用中文沟通；构建和下载日志静默保存，仅汇报关键结果与错误。
- 采用最小正确实现；优先复用已有服务，不重新引入一套转录运行时。
- 保留用户当前模型、Mode、Prompt、上下文开关和数据；迁移前后比较实际配置。
- **不得修改现有「中文 V3」润色 Prompt**，包括正文、ID 和 `useSystemInstructions`。
- ASR 初始提示与润色 Prompt 是两回事。前者已完成通用提示 A/B，后者保持锁定。
- 不擅自修改 Clash mode、TUN、节点、系统代理或其他网络配置。
- 构建成功不等于实机可用；真实音频、权限、录音设备、快捷键和粘贴需要本机验证。

### 3.2 最新配置快照：不要误用历史偏好

2026-11-12 从用户偏好中核实：

| 配置 | 当前值 |
|---|---|
| 转录模型 | `ggml-large-v3`，Whisper Large v3 |
| 转录语言 | `zh` |
| Dictation 润色 provider | `Ollama` |
| Dictation 润色模型 | **`ornith-1.5:9b`** |
| Dictation Ollama server ID | `379E260D-4F3E-4C7D-A1D0-C7F569228DC7`，远端服务器 |
| 剪贴板 / 选中文本 / 屏幕 OCR | 均开启 |
| `PrewarmModelOnWake` | 未显式保存，当前代码按默认 `true` 处理 |

历史上已充分测试并获得良好反馈的本地润色方案是 `qwen3.5:2b-q4_K_M`。它是重要性能基线，**不是截至本次交接时用户正在使用的模型**。不要在升级时自动将远端配置改回本地 2B。

本地服务器历史固定 ID 为 `20000000-0000-0000-0000-000000000001`，地址为 `http://127.0.0.1:11434`。远端地址从现有用户配置读取，本文不复制内网地址。

锁定的润色 Prompt：

- ID：`AFEAC1E3-CF39-4985-B22C-9AC075CE8292`
- 标题显示为「中文 V3」，持久化标题含末尾空格；不要顺手重命名。
- `useSystemInstructions = false`
- 正文字符数：1370
- 正文 UTF-8 SHA-256：`1360d3838ad5f246bc4236b8d3300fa35a674567f6498df5cbd1ad240fd1abd7`
- 正文保存在用户 `customPrompts` 偏好中，不是仓库内的内置模板；应通过本机配置备份保留。

Whisper 中文 ASR 提示已改为：

> 以下是日常口述内容，可能包含中文、英文、数字、产品名和技术术语。

源代码默认值、用户 `TranscriptionPrompt` 和 `CustomLanguagePrompts.zh` 均已同步。保留该覆盖，不能被上游的旧问候语恢复。

### 3.3 用户数据不在代码仓库中

- 配置域 / Bundle ID：`com.prakashjoshipax.VoiceInk`
- 用户数据目录：`~/Library/Application Support/com.prakashjoshipax.VoiceInk/`
- 转录与统计数据库：`default.store`、`stats.store`；词典数据库：`dictionary.store`
- 录音：上述目录的 `Recordings/`
- Whisper 模型：上述目录的 `WhisperModels/`
- TranscribeCpp 模型：上述目录的 `TranscribeCpp/`

源码迁移不会搬走这些运行数据。安装升级前应做一致性备份；SQLite 处于 WAL 模式时，不能只复制一个仍在写入的 `.store` 文件。真实录音、数据库、完整偏好、用户额外下载的模型权重与证书私钥不作为源码或 Actions 产物提交。上游自带的提示音和 Silero VAD 资源属于项目文件，应保留。

## 4. 必须迁移的定制能力与代码位置

以下路径均相对当前 2.11 定制版根目录；2.27 已将大部分文件移入 `App/`、`Features/` 和 `Infrastructure/`。

| 能力 | 当前主要文件 / 测试 |
|---|---|
| 多 Ollama server、离线缓存、精确 endpoint 路由 | `VoiceInk/Services/OllamaServerConfiguration.swift`、`OllamaService.swift`、`VoiceInk/Services/AIEnhancement/AIService.swift`；`OllamaServerConfigurationTests.swift` |
| 每个 Mode 独立 Server + Model | `VoiceInk/Modes/ModeConfig.swift`、`ModeConfigDraft.swift`、`ModeRuntimeConfiguration.swift`、`ModeConfigFormView.swift`、`ModeFormWarmupStore.swift`；`ModeOllamaConfigurationTests.swift` |
| Ollama 管理 UI 不向错误 server 写入选择 | `VoiceInk/Views/AI Models/ProviderLocalManagementView.swift` |
| Ollama server 的备份与导入兼容 | `VoiceInk/Services/BackupTypes.swift`、`BackupImporter.swift`、`ImportExportService.swift` |
| 本地 Ollama 请求与预热 | `VoiceInk/Services/OllamaService.swift`、`OllamaServerConfiguration.swift`、`ModelPrewarmService.swift`、`VoiceInk/VoiceInk.swift` |
| 历史累计统计保护 | `LegacyStatsCarryForwardService.swift`、`SessionMetricMigrationService.swift`、`SessionMetricWriteCoordinator.swift`、Dashboard stats 系列；对应两个统计测试文件 |
| 中英混排格式 | `VoiceInk/Transcription/Processing/MixedScriptTypographyNormalizer.swift`、`VoiceInk/Transcription/Engine/TranscriptionPipeline.swift`；`MixedScriptTypographyNormalizerTests.swift` |
| 已选 Whisper 模型不被 onboarding 重置 | `VoiceInk/Views/Onboarding/` 下相关文件；`OnboardingLocalModelSelectionTests.swift` |
| Qwen3-ASR 实验入口 | `VoiceInk/Transcription/TranscribeCpp/`、`VoiceInk/Models/TranscriptionModelRegistry.swift`、`LanguageDictionary.swift`；`Qwen3ASRIntegrationTests.swift` |
| 已验证的 Whisper 通用提示 | `VoiceInk/Transcription/Whisper/WhisperPrompt.swift` |
| 本地构建与签名 | `Makefile`、`LocalBuild.xcconfig`、`VoiceInk/VoiceInk.local.entitlements`、项目与依赖锁定文件 |

上述测试文件位于 `VoiceInkTests/`，此前未跟踪的测试和新增服务均已纳入定制基线提交。

### 4.1 Ollama 不可丢失的行为

- 持久化键：`ollamaServerConfigurationsV1`；Mode 通过 `selectedOllamaServerID` 关联。
- 离线服务器及缓存模型保留，不能因刷新失败丢失选择。
- 请求使用 Mode 已解析的精确 `baseURL` 与模型，不能回退到另一个可连接服务器。
- `temperature` 放入 JSON 的 `options`；`think = false`。
- loopback 请求使用 `options.num_ctx = 4096`；开启预热时 `keep_alive = "30m"`。
- 启动 / 唤醒仅自动预热符合条件的 loopback Ollama，不能拿用户的远端 server 做同样处理。
- `PrewarmModelOnWake` 未保存时按 `true`；关闭时的请求行为有对应测试。
- `num_keep` 曾测试 256 / 512，均变慢，已淘汰；没有为此写代码，不要重复引入。
- 保留完整窗口 OCR 上下文的既有语义，不因简化请求而擅自裁剪。

### 4.2 统计保护的原因

历史版本清理过大量逐条转录，只剩累计统计，不能从现存数据库行数重算全部历史。迁移采用 cutover 快照及 lifetime carry-forward：

```text
升级后的累计值 = 历史累计值 + 当前统计值 - cutover 时已被当前统计代表的值
```

不能伪造有时间戳的历史会话，也不能给日/月统计重复叠加 lifetime 数据。保留幂等性、损坏主状态的备份恢复、并发写入去重与缓存失效行为。原上游统计迁移不足以替代这些定制。

## 5. ASR 已完成的实验与结论

这些是先前在本机真实录音上的探索性结果，不是正式 WER/CER 数据集，也不等于所有音频都更好。临时 JSON / 日志已清理，原录音仍在本机。

### 5.1 Whisper Large v3 与 Qwen3-ASR

12 条真实录音对照中：

| 指标 | Whisper Large v3 | Qwen3-ASR 1.7B Q5 |
|---|---:|---:|
| 转录中位耗时，不含显式模型加载 | 约 3.00 s | 约 1.44 s |
| 隔离测量的加载 RSS 增量 | 约 3415 MiB | 约 2208 MiB |

Qwen 修正过「体感」「转录模型」「过拟合」「Qwen3 的 ASR」，但也出现：

- `Refine V1` → `汝川位移`
- `1234` → `一二三四`
- `重新问我` → `重新喂我`
- 某条开头出现「润色模式，润润色模型」

5 条代表性录音的 Qwen 自动语言与强制中文输出相同。因此 **Qwen 保留为实验性选项，不替换当前 Whisper 默认模型**。

注意：Whisper 测试中复用了已加载模型；Qwen 服务每次转录结束会卸载，测试单独记录了各次加载。RSS 是加载前后差值，未测完整推理峰值；端到端比较应计入真实加载与预热行为。不能只凭这组数字承诺安装后的整体延迟。

### 5.2 固定广告字幕幻觉与有效缓解

用户说「清理无用的过程文件」，Whisper 却输出「请不吝点赞 订阅 转发 打赏支持明镜与点点栏目」。

精确录音：`BFC5BD10-AC0F-4211-A1FD-EAC7ABC18B44.wav`，长约 2.093 s，RMS 约 -31.5 dB，不是全静音。

| 同一 WAV 的配置 | 输出 |
|---|---|
| Whisper 旧提示：你好，最近好吗？见到你很高兴。 | 可复现上述广告句 |
| Whisper 通用口述提示 | 清理无用的过程文件。 |
| Qwen 自动语言 | 清理无用的过程文件。 |
| Qwen 强制中文 | 清理无用的过程文件。 |

通用提示在其他样本还修正过 `T感 → 体感`；在该严重幻觉样本上收益明确，故已采用并复测。结论仅支持缓解已测问题，**不能声称根除 Whisper 幻觉或已证明旧提示是唯一根因**。没有加广告句黑名单。

另一条技术口述回归音频：`2AA51A2D-5397-4AE9-BBC3-54688EB04132.wav`，约 30 s。

### 5.3 Qwen 实现与模型

无需 `mlx-swift-asr`、Python 子进程或第二套 ML 依赖。现有 `TranscribeCpp 0.2.0-dev.856d7c1` 已能原生运行 Qwen。

| 项目 | 固定值 |
|---|---|
| 模型名 | `qwen3-asr-1.7b-q5-k-m` |
| HF repository | `handy-computer/Qwen3-ASR-1.7B-gguf` |
| revision | `92282af1610a2db19d66f2bef1e260f5deca782d` |
| 文件 | `Qwen3-ASR-1.7B-Q5_K_M.gguf` |
| 字节数 | `1517290464` |
| SHA-256 | `034c557fe92ff8fcd9a9c041cbdaad347be0a86a58d3a348f63cf3f0180879d0` |

模型已在本机下载并核对大小、SHA-256；不随仓库提交。GGUF 自包含，无需独立 tokenizer。中文显式语言提示在该精确二进制上已实测成功；上游部分文字文档说不支持，不能据此覆盖真实结果。

已知边界：

- 原生生成上限为 256 tokens；服务用约 35 s 能量边界分块，遇到截断仍抛错，不静默返回不完整文本。
- Qwen 和 Cohere 使用独立服务实例，避免共享加载槽互相取消。
- `auto` 映射为原生 `nil`，按分块检测语言连接文本。
- Qwen 不使用 Cohere 路径的英文 ITN 后处理。
- 非流式，无真实词级时间戳；该运行时没有 Qwen 任意上下文 / hotword 参数，单分块中途取消能力有限。

## 6. 上游升级调查

2026-11-12 核实最新正式版为 **2.27**，发布于 2026-11-11。相对当前上游基线约 285 个提交；大量文件移动与本地化变化。35 个本地已修改文件中，34 个对应路径也被上游改动或移动，**不是已确认有 34 个文本冲突**。

值得升级的内容：粘贴与剪贴板恢复、资源清理顺序、录音与快捷键恢复、空录音处理、选中文本 / OCR 捕获、词典与术语处理，以及减少隐藏 Dashboard 查询和重复状态刷新。

必须提前处理：

1. `v2.27` 锁定 MLX Swift 0.33.0，其 manifest 要求 Swift 6.3；本机 Xcode 26.3 / Swift 6.2.4 不能直接按该锁定构建。以依赖 manifest 和实际构建为准，不能只信上游 README 的 Swift 6.2+。
2. macOS runner 应固定可用 Xcode，输出 `xcodebuild -version` / `swift --version` 并检查要求。MLX-LM 的 FoundationModels 等 SDK/API 兼容性仍需实际构建确认。
3. 2.27 仍只有单 Ollama endpoint 的上游逻辑，没有我们的多 server / 本地请求优化；必须迁移。
4. 上游将 Cohere 服务改名为 `OfflineTranscribeCppService` 并新增 SenseVoice。应复用新通用路径迁移 Qwen，保留模型隔离和错误语义。
5. 上游仍含旧 Whisper 中文问候语；已保存的用户覆盖及源码默认修正要保留。
6. 上游润色请求经过新的统一 chat-completion 路径，不能只解决编译而漏掉精确 Ollama 路由和上下文。
7. 新版 `make local` 使用 Release，Debug 应用改为 `VoiceInk Dev.app` / `.dev` Bundle ID；正式更新应保留原生产 Bundle ID，不能误装成另一份用户数据空间。
8. 上游 `LocalBuild.xcconfig` 已修正签名身份覆盖问题；当前定制版还以最终重签处理。迁移时验证最终产物，不只看构建日志的身份参数。
9. 新版默认启用词典 Auto Learn；Smart Punctuation 默认关闭且当前主要处理 ASCII 场景。先记录新功能的默认行为，避免把自动词典修正带入未经控制的 ASR 基线对照。

截至交接，尚未执行 2.27 合并或在新目录构建 2.27。

## 7. 新 GitHub 仓库的绑定与首次推送（已完成）

用户创建了私有空仓库 `AaronJny/VoiceInk`。原上游历史、LICENSE、当前定制代码和全部新增测试均已保留；没有提交运行数据、下载的 ASR 权重、构建缓存或签名私钥包。

以下是已执行的初始化流程记录，不需要再次重命名远端：

```bash
# 在 /Users/aaron/code/tools/VoiceInk 中先审查
git status --short
git diff
git log --oneline -10
git remote -v

# 定制代码提交 eb6ab17 后绑定远端
git remote rename origin upstream
git remote add origin git@github.com:AaronJny/VoiceInk.git

# 补齐原浅克隆缺少的历史
git fetch --unshallow upstream

# 将当前已提交的定制分支作为新仓库 main，而不是推送旧本地 main
git push -u origin HEAD:main
```

已通过 GitHub API 核对远端 `main` 的代码基线 commit 和默认分支。用户可将新仓库授权给 Codex，明确以该 `main` 的定制基线工作。后续升级放在单独分支，保留 `upstream` 追踪官方仓库。

## 8. GitHub Actions 构建方案

上游当前基线和已核实的 `v2.27` 均没有检入 `.github/workflows/` 构建流程，需要新增最小 workflow。

建议先支持手动触发，再在需要时加入常规提交构建。Codex 修改代码和读取 Actions 结果，Xcode 编译由 macOS runner 执行；若 Codex 的任务环境是 Linux，不在那里直接运行 `xcodebuild`。

构建路径应明确：

1. 检出准确 commit，选择 macOS ARM64 runner 和固定 Xcode，记录版本与架构。
2. 获取锁定依赖。当前旧版为 MLX 0.31.4 / MLX-LM `d2424294…`；目标 2.27 为 MLX 0.33.0 / MLX-LM `c8dabc63…`。不要混用两个版本的依赖锁定。
3. 准备 Whisper XCFramework。当前本机使用过校验的官方 whisper.cpp v1.9.2 工件；仓库 Makefile 的缺省路径仍可能 clone/pull 移动版本。CI 应固定版本 / revision 与工件校验，不能依赖用户主目录已有文件。
4. 使用 `LOCAL_BUILD` 和本地 entitlements 构建自用版本，不接入生产 CloudKit。旧生产配置曾让测试宿主因 CloudKit entitlement 缺失而在测试开始前 trap。
5. 跑不依赖真实录音和模型权重的聚焦测试；真实 ASR benchmark 单列为本机任务。
6. 使用第 9 节的固定身份签名，验证后打包。
7. 先用 `ditto` 将 `.app` 打成 zip，再上传单个 zip 工件，保留 bundle 的权限与符号链接。附 commit、版本、工具链、架构及签名身份的构建信息。

GitHub 已提供 macOS ARM64 镜像及更新的 Xcode；可用镜像标签、Xcode 安装路径和 Metal 编译组件在实施时重新核实。先保证可靠构建，再根据耗时添加依赖缓存，不复制本机旧路径下的 DerivedData。

当前 `make local` 是 Debug，最终会显式重签；上游 2.27 是 Release，且修正了 xcconfig 的身份覆盖。迁移 workflow 时应选定正确版本的入口，不硬套旧产物路径或误产出 `.dev` 应用。

## 9. 云端统一签名：推荐沿用现有身份

### 9.1 已核实的本机身份

| 项目 | 值 |
|---|---|
| 证书名称 | `VoiceInk Local Dev` |
| 证书类型 | 自签名代码签名证书；subject 与 issuer 相同 |
| SHA-1 / codesign identity | `24F8BA788091EF77E65B03212711783CF66232C6` |
| SHA-256 指纹 | `0D:8A:10:DA:62:7B:13:4F:22:C2:B6:AB:7F:B2:D7:CF:E5:E4:A0:B4:62:D6:BC:2F:F0:C4:37:F2:01:3D:71:29` |
| 有效期截止 | 2027-04-01 04:30:44 UTC |
| 应用 Bundle ID | `com.prakashjoshipax.VoiceInk` |
| 安装路径 | `/Applications/VoiceInk.app` |
| TeamIdentifier | 未设置，不是 Apple Developer ID 身份 |

当前安装应用的 designated requirement 是：

```text
identifier "com.prakashjoshipax.VoiceInk" and certificate leaf = H"24f8ba788091ef77e65b03212711783cf66232c6"
```

**统一签名与编译发生在本机还是云端无关，关键是同一证书及其对应私钥。** 只新建一个同名证书，或者每次使用 ad-hoc 签名，都不能保留这一身份。

### 9.2 一次性导出与仓库配置（已完成）

复杂度是一次性的 CI 配置，范围可控，不需要重写应用，也不必为当前个人使用方案立即购买 Apple Developer 账户。

按原 SHA-1 精确选择身份，通过 macOS Security API 导出加密 `.p12`，没有批量导出其他钥匙串身份。已将导出包仅导入进程内存，核对证书指纹、私钥存在，并完成一次私钥签名 / 公钥验签，验证导出可用；没有新建替代证书。

本机加密备份：

- 文件：`~/Library/Application Support/VoiceInk Signing/VoiceInk Local Dev.p12`
- 目录权限：`0700`；文件权限：`0600`。
- 随机导出口令保存在本机钥匙串的通用密码项目中：service 为 `VoiceInk GitHub Signing`，account 为 `AaronJny/VoiceInk`，label 为 `VoiceInk Local Dev PKCS12 export password`。
- 未将口令写入磁盘明文文件、命令参数、终端输出或仓库。

`AaronJny/VoiceInk` 的 Actions Secrets 与变量已通过 GitHub CLI 配置并核对名称：

| 项目 | GitHub 配置 | 用途 |
|---|---|---|
| `.p12` 的 Base64 | Secret `SIGNING_CERTIFICATE_P12_BASE64` | 包含证书与私钥 |
| `.p12` 导出口令 | Secret `SIGNING_CERTIFICATE_PASSWORD` | runner 导入使用 |
| 固定 SHA-1 | Variable `SIGNING_IDENTITY_SHA1` | 明确选择原身份；值为上表 SHA-1 |

临时钥匙串口令可在每次 CI 任务中随机生成，无需长期保存。上述 Secrets 已准备好，Codex 的 workflow 只需引用对应名称，不必再次索要私钥或口令；不将 Secret 值写进文档、源码、日志或对话。仓库 `.gitignore` 已排除 `.p12` / `.pfx`。

### 9.3 workflow 的签名职责

- 在 runner 临时目录创建钥匙串，解码并导入 `.p12`，配置 `codesign` 对私钥的非交互访问。
- 自签名证书在全新 runner 上的信任设置需要首轮实际验证；导入后用 `security find-identity -v -p codesigning` 确认原 SHA-1 可用，不能假设本机信任会自动迁移。
- 为构建 / 最终签名显式使用固定 SHA-1，保留原 Bundle ID、所需 entitlements、嵌套代码与 XPC 的一致身份。
- 先处理嵌套代码，再签主应用；不要仅因主包显示正确名称就认为所有内容已统一。
- 签名密钥只提供给可信的构建任务，不提供给外部 PR 代码。普通无密钥编译检查与签名产物任务可分开。
- 正式自用产物任务如果找不到原身份应失败，不悄悄回退到 ad-hoc。
- 在始终执行的清理步骤删除临时证书文件和钥匙串。

对最终解压产物运行：

```bash
codesign --verify --deep --strict /path/to/VoiceInk.app
codesign -dv --verbose=4 /path/to/VoiceInk.app
codesign -dr - /path/to/VoiceInk.app
```

验收应比较 leaf 指纹 / designated requirement、Bundle ID、entitlements 和嵌套签名，不比较每次构建都会变化的 CDHash。

相同身份、Bundle ID 和安装路径有利于延续权限与钥匙串访问，**不能保证所有 macOS 权限在任何升级中都不再询问**；需要对比 entitlements 并实机升级验证。证书到期轮换也应单独处理，不能悄悄更换身份。

这套自签名方案适合用户自己的 Mac，不等于 Apple Developer ID 签名与公证。若以后要给其他用户提供正常分发 / 公证版本，再引入 Developer ID、Hardened Runtime 和 notarization；届时需单独设计身份迁移。

截至本次更新，已完成本机导出、密码保护、指纹与私钥回环验证和 GitHub 配置。**尚未在真实 GitHub runner 中验证证书导入、信任配置及最终应用签名**；这部分由后续 workflow 实现和验证。

## 10. 验证入口与验收标准

### 10.1 当前本机环境与既有验证

- Apple M1 Pro，32 GB RAM。
- Xcode 26.3 / Swift 6.2.4。
- 现有定制版使用以下命令成功构建并校验过签名：

```bash
make local LOCAL_CODESIGN_IDENTITY='VoiceInk Local Dev'
```

本机曾出现的构建问题：

- Xcode 宏信任：现有入口使用 `-skipMacroValidation`；新版本还可能需要 package plugin 参数，以锁定依赖为准。
- 旧 Whisper 工件出现重复 modulemap 输出：已换为校验过的 v1.9.2 工件。
- Metal 编译组件缺失：本机安装过所需组件；云端另行确认。
- 旧 MLX-LM 与 MLX 版本不匹配：当前通过固定 `d2424294…` / 0.31.4 解决；升级时不应盲目保留不匹配组合。
- `LocalBuild.xcconfig` 曾覆盖命令行签名身份；当前 Makefile 的最终重签是实际生效路径，上游已另有修复。

### 10.2 聚焦测试

当前测试目标 `VoiceInkTests` 中应保留并运行：

```text
LegacyStatsCarryForwardTests
SessionMetricWriteCoordinatorTests
OllamaServerConfigurationTests
ModeOllamaConfigurationTests
MixedScriptTypographyNormalizerTests
OnboardingLocalModelSelectionTests
Qwen3ASRIntegrationTests
```

下面是 **现有 2.11 定制版** 的本机聚焦命令示例；升级后需核对新的测试目录、Release / Debug 身份及 TEST_HOST：

```bash
xcodebuild \
  -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .local-build \
  -xcconfig LocalBuild.xcconfig \
  -skipMacroValidation -skipPackageUpdates -onlyUsePackageVersionsFromResolvedFile \
  -parallel-testing-enabled NO \
  -only-testing:VoiceInkTests/LegacyStatsCarryForwardTests \
  -only-testing:VoiceInkTests/SessionMetricWriteCoordinatorTests \
  -only-testing:VoiceInkTests/OllamaServerConfigurationTests \
  -only-testing:VoiceInkTests/ModeOllamaConfigurationTests \
  -only-testing:VoiceInkTests/MixedScriptTypographyNormalizerTests \
  -only-testing:VoiceInkTests/OnboardingLocalModelSelectionTests \
  -only-testing:VoiceInkTests/Qwen3ASRIntegrationTests \
  CODE_SIGN_IDENTITY='VoiceInk Local Dev' \
  CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM='' \
  CODE_SIGN_ENTITLEMENTS="$PWD/VoiceInk/VoiceInk.local.entitlements" \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) LOCAL_BUILD' \
  test
```

聚焦测试在之前的开发阶段分别执行过，不代表本文编写时重新全量运行过。最后的 Qwen 聚焦测试、真实 WAV 回放、本地构建和深度签名校验已通过；2.27 的测试尚未进行。

### 10.3 ASR benchmark 注意事项

入口：`VoiceInkTests/ASRBenchmarkTests.swift`。

- 环境变量：`VOICEINK_ASR_BENCHMARK_FILES`，用换行分隔绝对文件路径；输出为 `VOICEINK_ASR_BENCHMARK_OUTPUT`。
- Xcode 宿主不一定继承 shell 变量，因此还支持用户偏好 `ASRBenchmarkFiles`（字符串数组）和 `ASRBenchmarkOutput`。
- 无输入时测试直接返回。因此 CI 显示该测试通过，**不代表做过 ASR 质量测试**。
- 需要本机的 Whisper / Qwen 已安装模型和真实 WAV；不要将这些数据上传以换取一个 CI 绿色状态。
- 测试当前会比较「当前用户提示」和写死的通用候选；自从当前提示也改为该候选后，两路相同。复现旧问候语问题时要明确传入旧提示，不能把两路相同当作有效 A/B。
- 用独立进程 / 单 runner 关闭测试并行，记录预热、加载、推理和误识别；短期关闭预热时先记录原偏好，结束后恢复原值或删除原本不存在的键。
- 测试结束清理 benchmark 偏好和临时转录日志，保留原始用户录音。

### 10.4 升级完成标准

- [x] 完整定制代码及新增测试已作为基线推送至用户仓库 `main`；官方仓库保留为 `upstream`，本文随交接提交保存。
- [x] 原身份已导出、完成指纹和私钥回环验证，签名 Secrets 与固定身份变量已配置。
- [ ] Actions 从干净环境按锁定依赖构建，无本机旧目录依赖；产物能追溯到准确 commit。
- [ ] 云端产物使用同一证书，主应用和嵌套内容签名验证通过，未回退到 ad-hoc。
- [ ] 2.27 升级后，现有 Mode / 模型 / server ID / Prompt / 上下文开关保持；特别注意当前远端 `ornith-1.5:9b`。
- [ ] 「中文 V3」正文 SHA-256 不变，Whisper 通用中文提示仍生效。
- [ ] 历史累计会话、字数、时长不减少、不重复，新增会话只计一次。
- [ ] 多 Ollama 精确路由、离线选择、备份导入、本地请求参数及 loopback 预热回归通过。
- [ ] Qwen 仍是实验选项；Whisper 广告样本和技术口述样本完成真实回放，不将失败结果静默视为完整转录。
- [ ] 本机验证麦克风 / 辅助功能 / 屏幕录制权限、录音快捷键、睡眠唤醒、剪贴板恢复、粘贴和 OCR。
- [ ] 只有通过本机升级验证后，才将新产物作为日常安装版；旧应用与一致性数据备份可回退。

## 11. 可直接交给 Codex 的任务说明

> 先阅读根目录 HANDOFF.md，并核对实际 Git 状态。这个仓库是 VoiceInk 的定制版，不是纯上游；基线代码和测试已推送到 AaronJny/VoiceInk 的 main，签名 Secrets 与固定身份变量也已配置。基于现有基线打通 GitHub Actions macOS 构建与同一证书的云端签名，再在升级分支整合已核实的 v2.27。不得改动「中文 V3」润色 Prompt，不得将历史本地 Qwen 2B 偏好误当成用户当前远端 ornith 配置。重点保留多 Ollama 路由与预热、历史累计统计、混排格式、Whisper 通用提示和 Qwen3-ASR 实验入口。报告实际完成的构建和测试；Linux 环境无法进行的 macOS 构建交给 Actions，真实录音与权限测试留给本机。workflow 引用已有签名 Secrets，不要索要或输出私钥正文。实现保持最小、可审查、可回退，并全程用中文沟通。

## 12. 参考来源

- [VoiceInk v2.27 正式版](https://github.com/Beingpax/VoiceInk/releases/tag/v2.27)
- [v2.27 构建说明](https://github.com/Beingpax/VoiceInk/blob/v2.27/BUILDING.md)
- [MLX Swift 0.33.0 manifest](https://github.com/ml-explore/mlx-swift/blob/0.33.0/Package.swift)
- [GitHub macOS runner 镜像](https://github.com/actions/runner-images/tree/main/images/macos)
- [GitHub Actions 安装签名证书](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)
- [Qwen GGUF 固定 revision](https://huggingface.co/handy-computer/Qwen3-ASR-1.7B-gguf/tree/92282af1610a2db19d66f2bef1e260f5deca782d)

参考来源按交接日核实。运行环境、用户配置与上游发布之后可能变化，继续操作前应重新核对相关项。
