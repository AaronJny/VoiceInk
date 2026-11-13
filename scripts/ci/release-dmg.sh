#!/usr/bin/env bash
set -euo pipefail
SOURCE="$GITHUB_SHA"
TAG="${REQUESTED_TAG:-${GITHUB_REF_NAME#release/}}"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+-personal\.[0-9]+$ ]]
# Do not reuse a different revision merely because it was the latest green run.
run_id=$(gh api "repos/$GH_REPO/actions/workflows/macos-build.yml/runs?head_sha=$SOURCE&status=completed&per_page=100" \
  --jq ".workflow_runs | map(select(.head_sha == \"$SOURCE\" and .conclusion == \"success\" and (.head_branch == \"main\" or (.head_branch | startswith(\"upgrade/\"))))) | first | .id // empty")
[[ "$run_id" =~ ^[0-9]+$ ]] || { echo 'No successful build for this exact commit.' >&2; exit 1; }
mkdir -p release-assets
gh run download "$run_id" --name "VoiceInk-DMG-$SOURCE" --dir release-assets
cd release-assets
SOURCE="$SOURCE" SOURCE_RUN="$run_id" python3 - <<'PY'
import hashlib,json,os
from pathlib import Path
m=json.loads(Path('dmg-info.json').read_text())
p=Path('VoiceInk-2.27-arm64.dmg')
assert m['sourceCommit']==os.environ['SOURCE']
assert str(m['sourceRun'])==os.environ['SOURCE_RUN']
assert str(m['packagingRun'])==os.environ['SOURCE_RUN']
assert m['packagingCommit']==os.environ['SOURCE']
assert m['file']==p.name and m['bytes']==p.stat().st_size
assert m['sha256']==hashlib.sha256(p.read_bytes()).hexdigest()
assert m['certificateSHA1']=='24F8BA788091EF77E65B03212711783CF66232C6'
t=m['testSummary']
assert t['totalTestCount']>0 and t['failedTests']==0 and t['skippedTests']==0
assert Path('SHA256SUMS.txt').read_text()==m['sha256']+'  '+p.name+'\n'
Path('release-notes.md').write_text(f'''## VoiceInk 2.27 定制版（Apple Silicon / ARM64）

保留原有个性化功能。本次修复 Auto Learn 把发送后的编辑框占位文字误当作手动更正的问题，保留发送清空前实际观察到的手动修改，并改进中文纠正候选提取。保留 personal.2 的远程 Ollama 设置与独立审核服务器、模型选择。

### 安装
下载 **VoiceInk-2.27-arm64.dmg**，退出旧版后打开 DMG，将 VoiceInk 拖入 Applications。升级前请备份原应用和数据。

### 验证
- 10 组、{t['totalTestCount']} 项回归测试通过，无失败或跳过。
- 原 VoiceInk Local Dev 证书签名；20 个代码路径、完整应用及挂载后签名复验通过。
- DMG 通过 hdiutil 验证和只读挂载，文件哈希、权限、符号链接与原签名包一致。
- 源码：`{m['sourceCommit']}`；构建运行：`{m['sourceRun']}`。
- 未经 Apple 公证；真实 Mac 上的录音与本机/远端服务交互仍需实际使用确认。

不扩大输入观察范围，不增加键盘监听权限。发送清空时保留已观察到的真实修改；若目标应用未提供变更通知，或修改与发送合并而未能读取中间内容，仍可能漏检。真实目标应用的可访问性行为仍需实际使用确认。

附 SHA256SUMS.txt 与 dmg-info.json。
''')
PY
EXPECTED=$(python3 -c 'import json;print(json.load(open("dmg-info.json"))["sha256"])')
if gh release view "$TAG" >/dev/null 2>&1; then
  echo 'Release already exists; inspect before retrying. Never overwrite published assets.' >&2
  exit 1
fi
gh release create "$TAG" --target "$SOURCE" --title "VoiceInk 2.27 定制修正版 · $TAG" --notes-file release-notes.md --draft
gh release upload "$TAG" VoiceInk-2.27-arm64.dmg SHA256SUMS.txt dmg-info.json
gh release view "$TAG" --json assets --jq '.assets[].name' | sort > assets.actual
printf '%s\n' SHA256SUMS.txt VoiceInk-2.27-arm64.dmg dmg-info.json | sort > assets.expected
diff -u assets.expected assets.actual
gh release edit "$TAG" --draft=false --latest
mkdir downloaded
gh release download "$TAG" --pattern 'VoiceInk-2.27-arm64.dmg' --dir downloaded
printf '%s  %s\n' "$EXPECTED" downloaded/VoiceInk-2.27-arm64.dmg | sha256sum -c -
test "$(gh api "repos/$GH_REPO/git/ref/tags/$TAG" --jq '.object.sha')" = "$SOURCE"
gh release view "$TAG" --json url,isDraft,tagName,assets
