#!/usr/bin/env bash
set -euo pipefail
TAG=v2.27-personal.1
SOURCE=f455c8d841b4f39c4923aaedcc6a806cea3b10d0
EXPECTED=b2383d819519f48c7d4e8288e97391fa27ba782200dfcb28b3f724ecbe36c860
cd release-assets
printf '%s  %s\n' "$EXPECTED" VoiceInk-2.27-arm64.dmg | sha256sum -c -
python3 - <<'PY'
import json
from pathlib import Path
m=json.loads(Path('dmg-info.json').read_text())
assert m['sourceCommit']=='f455c8d841b4f39c4923aaedcc6a806cea3b10d0'
assert m['sha256']=='b2383d819519f48c7d4e8288e97391fa27ba782200dfcb28b3f724ecbe36c860'
assert m['bytes']==Path('VoiceInk-2.27-arm64.dmg').stat().st_size==49403776
assert m['certificateSHA1']=='24F8BA788091EF77E65B03212711783CF66232C6'
PY
cat > release-notes.md <<'MD'
## VoiceInk 2.27 定制版（Apple Silicon / ARM64）

基于官方 v2.27，保留多 Ollama 服务与 Mode 精确路由、中文提示与混排处理、累计统计保护及实验性 Qwen3-ASR。定制版禁用官方自动更新，避免覆盖个性化功能。

### 安装
下载 **VoiceInk-2.27-arm64.dmg**，打开后将 VoiceInk 拖入 Applications。升级前退出旧版并备份原应用和数据。

### 验证
- Release 应用通过 7 组、49 项回归测试。
- 使用原 VoiceInk Local Dev 证书签名；20 个代码路径、完整应用及 DMG 挂载后签名复验通过。
- DMG 已通过 hdiutil 验证和实际只读挂载，应用文件哈希、权限与符号链接均与原签名包一致。
- 源码提交：`f455c8d841b4f39c4923aaedcc6a806cea3b10d0`。
- 未经 Apple 公证，用户 Mac 上的实际录音与升级验证仍待完成。

附 `SHA256SUMS.txt` 和 `dmg-info.json` 用于校验与追溯。
MD
# A new tag/release is intentional; never overwrite an existing published release.
if gh release view "$TAG" >/dev/null 2>&1; then
  echo 'Release already exists; inspect it instead of replacing assets.' >&2
  exit 1
fi
gh release create "$TAG" --target "$SOURCE" --title 'VoiceInk 2.27 定制版 · ARM64' --notes-file release-notes.md --draft
gh release upload "$TAG" VoiceInk-2.27-arm64.dmg SHA256SUMS.txt dmg-info.json
# Confirm exactly these three assets exist before making the release visible.
gh release view "$TAG" --json assets --jq '.assets[].name' | sort > assets.actual
printf '%s\n' SHA256SUMS.txt VoiceInk-2.27-arm64.dmg dmg-info.json | sort > assets.expected
diff -u assets.expected assets.actual
gh release edit "$TAG" --draft=false --latest
mkdir downloaded
gh release download "$TAG" --pattern 'VoiceInk-2.27-arm64.dmg' --dir downloaded
printf '%s  %s\n' "$EXPECTED" downloaded/VoiceInk-2.27-arm64.dmg | sha256sum -c -
test "$(gh api "repos/$GH_REPO/git/ref/tags/$TAG" --jq '.object.sha')" = "$SOURCE"
gh release view "$TAG" --json url,isDraft,tagName,assets
