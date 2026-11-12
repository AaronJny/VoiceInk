# sync-upstream-v211

## Session Context
- Task ID: 20260819-sync-upstream-v211
- Mode: temporary
- Status: active
- Scope: .
- Branch: planning/temp/20260819-sync-upstream-v211
- Created At: 2026-08-19 13:40:05
- Working Directory: `/Users/aaron/code/tools/VoiceInk`
- Repository Layout: standalone Git repository; subsequent work uses this directory
- Current Handoff: root `HANDOFF.md` (Chinese; updated 2026-11-12)

## Goal
Integrate pinned upstream VoiceInk `304db118` while safely preserving local statistics, signing, and Ollama capabilities.

## Current Phase
Custom code baseline published to AaronJny/VoiceInk main; signing export and GitHub Secrets configured. Handoff ready for Codex to implement cloud builds/signing and the v2.27 upgrade.

## Phase Planning

### Phase 1: Upstream Baseline And Statistics
- [x] Rebase session branch onto `304db118`
- [x] Verify clean upstream build
- [x] Implement lifetime carry-forward migration and tests
- [x] Pass Oracle data-integrity gate
- **Status:** complete

### Phase 2: Ollama Controls And Privacy
- [ ] Implement thinking tri-state
- [ ] Implement explicit image consent and request-scoped screenshots
- [ ] Add request/privacy tests
- [ ] Pass Oracle privacy gate
- **Status:** in_progress

### Phase 3: Integration And Release Validation
- [ ] Align local signing/docs with upstream workflow
- [ ] Run full validation and upgrade smoke tests
- [ ] Pass Oracle release-readiness gate
- **Status:** pending

## Key Questions
1. Can lifetime totals survive upstream migration without fabricating timestamped metrics?
2. Can Ollama images be proven absent unless both privacy gates are enabled?
3. Does the existing signing identity preserve permissions and Keychain access?

## Decision Log
| Decision | Rationale |
|----------|-----------|
| Use pinned upstream `304db118` | Includes post-v2.11 signing fixes and passes upstream build checks |
| Manually port retained behavior | Upstream architecture changed substantially and supersedes most local commits |
| Keep legacy totals as lifetime carry-forward | Only aggregate history remains for thousands of cleaned sessions |

## Errors & Solutions
| Error | Attempt | Solution |
|-------|---------|----------|
| `MLXHuggingFaceMacros` requires trust in CLI build | `make local` baseline | Re-run pinned dependency build with Xcode's explicit `-skipMacroValidation`; do not disable system security settings |
| Assumed CI workflow path did not exist | Read `.github/workflows/build.yml` | Use repository glob before reading optional workflow files |
| Duplicate `include/module.modulemap` outputs | Reused stale static Whisper XCFramework | Backed it up and installed checksum-verified official whisper.cpp v1.9.2 framework artifact |
| Metal compiler unavailable | First build with MLX dependencies | Installed Xcode Metal Toolchain 17C7003j |
| `MLXArray.maskFill` missing | SwiftPM selected MLX 0.31.4 for LM `cd1ab3d` | Pin LM parent `d2424294`, which is API-compatible with VoiceInk and MLX 0.31.4 |
| Delegated follow-up returned no result | Attempted narrow key-validation follow-up | Verified no files changed and completed the bounded patch and tests directly |
| Concurrent test did not compile | Missing Foundation macro import and main-actor annotation | Added the import/isolation and reran; concurrent two-context test passes |

## User-Provided Information
| Info | Source | Status | Verification |
|------|--------|--------|--------------|
| Begin implementation | User | Verified | Explicit request on 2026-08-19 |

## Session Log

### 2026-08-19 13:40
- Actions taken: created isolated temporary session worktree and deepwork state.
- Temporary findings: installed 1.72 app has 6,520 lifetime sessions but only 55 surviving transcription rows.
- Pending items: upstream baseline, statistics migration, Ollama port, release validation.

### 2026-08-19 13:48
- Actions taken: rebased session branch onto pinned upstream `304db118`; fetched all resolved packages; attempted signed baseline build.
- Temporary findings: Xcode 26.3 blocks the pinned MLX macro until explicitly trusted; `xcodebuild -help` provides `-skipMacroValidation` for non-interactive builds.
- Pending items: complete baseline build with explicit macro validation override.

### 2026-08-19 14:05
- Actions taken: installed required Xcode component; replaced stale Whisper artifact; pinned compatible MLX dependencies; completed clean baseline build and deep signature verification.
- Temporary findings: app bundle verifies but remains ad-hoc signed despite the identity override; resolve in Phase 3.
- Pending items: implement and test legacy statistics carry-forward.

### 2026-08-19 15:12
- Actions taken: implemented cutover snapshots and lifetime carry-forward; added incomplete-key guard; ran six focused tests and a full Debug build.
- Temporary findings: focused tests require `LOCAL_BUILD` because the hosted production test configuration attempts CloudKit startup.
- Pending items: Oracle data-integrity review, then Ollama privacy phase.

### 2026-08-19 15:35
- Actions taken: remediated all initial Oracle Gate 1 findings; added migration/recorder serialization, durable redundant state, in-memory fallback gating, physical metric counts, and generation-safe cache invalidation.
- Temporary findings: nine focused tests pass and the full Debug build remains successful.
- Pending items: read-only Oracle follow-up for Gate 1.

### 2026-08-19 15:45
- Actions taken: completed read-only Oracle follow-up; Gate 1 approved with no blocking/high findings.
- Temporary findings: initial follow-up used the wrong default directory; resumed with the exact worktree path and no permission-changing actions.
- Pending items: implement Ollama thinking and privacy-safe multimodal context.

### 2026-11-12: Repository relocation and upgrade preparation
- Migrated the current working tree to `/Users/aaron/code/tools/VoiceInk` as an independent Git repository, preserving the active branch, index, refs, tags, history, and all uncommitted/untracked project files.
- Verified identical source content, working-tree and staged diffs, and refs before updating this session log. Git object connectivity, project-file syntax, and new-directory build paths passed validation.
- Kept the original repository as a migration backup; excluded the approximately 6 GB `.local-build` cache from the copy.
- Latest verified upstream release: `v2.27` (`b5d1be9a7c7377dd059f37bb3e0f791b802d4001`, published 2026-11-11). Its MLX 0.33.0 dependency requires Swift 6.3; the local toolchain remains Swift 6.2.4 / Xcode 26.3.
- Preserve multi-server Ollama routing, local Qwen 3.5 2B request/prewarm settings, the unchanged Chinese V3 enhancement prompt, cumulative statistics, the verified Whisper Chinese ASR prompt, and experimental Qwen3-ASR support during the upgrade.
- GitHub Actions macOS ARM64 builds are feasible; pin an available Xcode and check Swift >= 6.3, producing a zipped app artifact. The initial local-signing option has been superseded by the user's preference for consistent cloud signing with the existing certificate; see `HANDOFF.md`. Real recording, OCR, shortcuts, and ASR performance remain local verification tasks.
- Neither the current baseline nor v2.27 provides a checked-in workflow. Workflow setup requires a user-owned GitHub repository. No commit, push, or upstream merge has been performed.

### 2026-11-12: Codex handoff and signing investigation
- Created `HANDOFF.md` with current Git state, retained custom behavior, ASR evidence, upgrade/build constraints, test entry points, repository setup, and the recommended cloud-signing path.
- Rechecked current preferences: Dictation now uses remote Ollama `ornith-1.5:9b`; local Qwen 3.5 2B remains a historical tested configuration, not the current selection. The locked Chinese V3 prompt still matches its recorded hash.
- Verified the installed app uses the self-signed `VoiceInk Local Dev` identity, SHA-1 `24F8BA788091EF77E65B03212711783CF66232C6`, valid through 2027-04-01. Same-certificate cloud signing is feasible, but private-key export, GitHub Secrets, and cloud import/signing have not been exercised.
- Next external input is the new repository URL. No signing private key was exported and no commit or push was performed.

### 2026-11-12: Repository publication and signing export
- User authorized binding/pushing to `https://github.com/AaronJny/VoiceInk` and exporting the existing private signing identity. The repository is private, Actions-enabled, and accessible with ADMIN permission.
- Exported only SHA-1 `24F8BA788091EF77E65B03212711783CF66232C6` as an encrypted PKCS12 outside the repository. In-memory import, certificate-fingerprint comparison, and private-key signing/public-key verification passed. The random export password is stored in the local Keychain, not a plaintext file or log.
- Configured Actions Secrets `SIGNING_CERTIFICATE_P12_BASE64`, `SIGNING_CERTIFICATE_PASSWORD`, and repository variable `SIGNING_IDENTITY_SHA1`; verified their metadata. Actual cloud import and application signing still await a workflow.
- Parsed all 42 changed/new Swift files, validated the Xcode project file and diff whitespace, and reviewed the staged baseline for credential patterns and accidental data files.
- Committed the complete custom code/test baseline as `eb6ab17b7bf74daab6c202cf5a5a08e8c9825b15` (47 files). Added ignores for PKCS12/PFX exports.
- Renamed the official remote to `upstream`, added `origin` for the user repository, and pushed the current branch to remote `main`. The local branch now tracks `origin/main`.
- Initial push failed because the original repository was shallow and lacked an early parent commit. `git fetch --unshallow upstream` restored the history; full Git integrity checks passed and the normal push succeeded without force or history rewriting.
- Updated `HANDOFF.md` with the actual repository, source baseline, signing backup location, existing Secrets, and remaining CI work. No 2.27 merge or cloud build has been performed.

## Task Summary
- What was learned:
- Pitfalls encountered:
- Reusable solutions:
