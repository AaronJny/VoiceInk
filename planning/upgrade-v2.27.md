# v2.27 升级与云构建记录

## 合并来源

- 定制基线：`f0bd061d182ea068be5196d32979eee7ee267ff8`（包含 `eb6ab17` 定制与 HANDOFF）。
- 官方正式版：`v2.27`，`b5d1be9a7c7377dd059f37bb3e0f791b802d4001`。
- 基线源树经 Git blob SHA 和完整 tree SHA 核对为 `10b32dfa4ff7c0a0643b51d156b916e087e21346`。
- 在共同祖先 `304db118f655fd99612c4a833820ae927df73881` 上进行三方合并，不是覆盖式替换。
- 上游完整历史已通过单独、不含签名 Secrets 的 Actions 导入并核对官方 commit，保存于 `vendor/upstream-v2.27`，升级提交保留双亲历史。

## 保留的行为

- 多 Ollama server、Mode 精确 endpoint/model、离线缓存、导入导出、本地参数与 loopback-only 预热。
- 将定制路由接入新版统一 chat-completion 路径；超时重试只针对同一 endpoint/model，缺失配置不回退。
- 历史累计统计 cutover、lifetime carry-forward、备份恢复、并发写入去重及缓存失效。
- 中文 Whisper 通用提示、混排格式化、onboarding 不重置已选模型。
- Qwen3-ASR 继续为实验选项；与 Cohere/SenseVoice 分别持有运行时实例，截断错误传播，不静默交付 partial 文本。
- 保留上游新增的录音、剪贴板、快捷键、OCR、模型目录与统一请求实现，采用完整 v2.27 依赖锁定。

## 构建和签名

见 `scripts/ci/README.md`。固定 macOS ARM64 / Xcode 26.6 / Whisper v1.9.2 校验工件，使用 GitHub Actions，不升级用户本机工具链。

`ci/cloud-baseline` 用原定制代码和 Debug 先验证；升级分支用 Release。签名步骤仅在受信本仓分支的 push / 手动运行中获得既有 Secrets。产物应保留生产 Bundle ID 和原证书，不得回退 ad-hoc。检查嵌套代码与 zip 解压后签名。

## CI 实测发现与修复

- 旧定制基线已在 Xcode 26.6 / Swift 6.3.3 / ARM64 上编译并通过七组 38 项聚焦测试。
- 新版 Release 应用已成功编译。首轮发现上游将测试父组移动到 `Tests/`，定制测试随之迁移至 `Tests/VoiceInkTests/` 并增加源文件路径预检查。修复后提交 `c4557e9cdd84ac81f4e4315b8f48992578159824` 的 Actions run `43239988651` 实测七组 48 项全部通过，0 失败、0 跳过；同轮签名因尚无临时信任而失败，不能把整轮标为通过。
- 新版 Assistant 追问路径已补齐初始 Mode endpoint 快照，后续不回退默认 Ollama；缺失 endpoint 明确失败。
- 原自签名身份成功导入，但 runner 将其标为不受信任，直接指定 SHA-1 签名仍失败。已获用户确认，只在临时 runner 为原证书设置 codeSign 用途信任。最终采用删除私钥/公有证书并让一次性 VM 销毁剩余信任记录的实际清理方式，完整签名产物已验证通过。
- LOCAL_BUILD 禁用官方 Sparkle 更新通道且不改写现有更新偏好，避免官方二进制覆盖个性化功能；普通上游构建行为不变。提交 `17556da29702ad834ca602c959fdd4b1078bddc4` 的 run `43244065239` 已完成七组 49 项（0 失败、0 跳过），并成功生成/验证跨 job 中间工件；签名步骤尚未通过。
- 快速 probe 证实原证书在临时 runner 的 codeSign 信任与钥匙串搜索列表同时正确时，可成功签名并通过 codesign 严格校验。最终原证书提取、完整应用签名与清理已由下述打包 run 实测，不以单个 probe 代替交付。
- 构建/聚焦回归与签名分为独立 job，同一 run 的源码与工件哈希绑定，可单独重试签名而不重复编译。

## 验证边界

- 合并阶段的 whitespace、冲突标记、Python/shell/YAML/依赖 JSON 与变更 Swift 语法检查已完成。
- Swift 类型检查、链接、七组聚焦回归和云签名以对应提交的 Actions 结果为准，不以本文件代替运行结果。
- 真实 WAV、M1 Pro 权限与安装升级未在云端执行；没有上传真实录音、数据库、偏好或模型权重。

## 安装前后必须核对

1. 关闭当前应用后，备份原 `.app`、完整偏好与一致性数据库（含 WAL 状态处理），保留可回退副本。应用内配置导出不包含历史统计数据库与 carry-forward 状态，不能替代此备份。
2. 保持当前 Whisper Large v3 / `zh`，远端 Ollama `ornith-1.5:9b` 及原 server ID，保留 Mode 和上下文开关。
3. 锁定「中文 V3」正文 SHA-256、ID、标题末尾空格、`useSystemInstructions=false`；不自动改回历史本地 Qwen 2B。
4. 验证原路径、Bundle ID、签名要求、权限、录音设备和快捷键、睡眠唤醒、粘贴/剪贴板恢复、选中文本/OCR。
5. 回放已记录的 Whisper 幻觉样本和技术口述样本；Qwen截断错误仍正确呈现。
6. 对照历史累计会话、字数、时长，无减少或重复；新增一次会话仅计一次。
7. 完成本机验收后才替换日常使用版。本记录没有宣称实机已经验证通过。

## 已交付云端安装包（2026-11-12）

- 完整打包 run：[43254833234](https://github.com/AaronJny/VoiceInk/actions/runs/43254833234)，全流程 success。
- [下载工件](https://github.com/AaronJny/VoiceInk/actions/runs/43254833234/artifacts/13961312554)，VoiceInk 2.27 (227)、ARM64、生产 Bundle ID。
- 应用源码 `17556da29702ad834ca602c959fdd4b1078bddc4`，打包脚本 `9055c81a15a9019959ea4fdb86c78e0973569cc8`；复用已通过七组 49 项测试的中间包，按来源 run / commit / SHA256 校验，没有重新编译或替换应用代码。
- 20 个代码路径的原证书指纹、strict 验签、entitlements、designated requirement 及 zip 解压复验通过。
- 内层安装 zip SHA256：`56aa650dd2d7e184eac31b0454ab83c35dcb46fb6222c8f0b95a195ffcaea56d`。
- 清理记录：私钥钥匙串和公有证书已删除、搜索列表已恢复；信任记录由一次性 runner 结束销毁，并非已手工删除。未公证；尚未替换用户 Mac 上的日常应用，实机验收仍待。
- 缓存冷构建 c6e012 同样 49 项通过；3 CPU / 7 GiB，编译 908 秒，测试 49 秒，SPM 与编译缓存已保存。不为测量再额外热跑。
