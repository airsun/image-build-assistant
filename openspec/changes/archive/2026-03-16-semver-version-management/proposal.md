## Why

当前构建流水线没有版本管理机制，每次构建使用时间戳作为镜像 tag（如 `20260316153532`），无法追踪版本演进，也无法避免无变更时的重复构建。需要引入 semver 版本管理，让 `projects.yaml` 成为版本状态的单一事实来源，并通过 git commit 对比实现智能构建决策。

## What Changes

- `projects.yaml` 新增 `built_commit` 字段，记录每个版本对应的源码 commit hash
- 构建前由 AI 层读取 `built_commit`，与目标仓库 HEAD 做 git diff：
  - 有变更 → auto bump patch 版本号，执行构建
  - 无变更 → 默认不构建，告知用户镜像已是最新；用户坚持则 bump 后构建
- 用户可指定目标版本号，但不能低于或等于当前版本（不允许倒退）
- 构建成功后自动更新 `projects.yaml` 的 `version` 和 `built_commit`
- `build.sh` 不做版本智能判断，只接收 `--version` 参数

## Capabilities

### New Capabilities
- `semver-versioning`: 基于 git diff 的 semver 版本管理机制，包括版本决策逻辑、自动 bump、倒退防护、构建后状态回写

### Modified Capabilities

## Impact

- `image-builder/projects.yaml` — 新增 `built_commit` 字段（schema 变更）
- `image-builder/scripts/project-resolver.sh` — 需要解析新的 `version` 和 `built_commit` 字段
- `image-builder/build.sh` — 确保 `--version` 参数正确传递，不再 fallback 到时间戳
- AI 层构建流程 — 新增版本决策逻辑（读 yaml → git diff → 决定版本 → 传参构建 → 回写 yaml）
