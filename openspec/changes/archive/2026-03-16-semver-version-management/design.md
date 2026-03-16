## Context

当前构建系统使用时间戳作为镜像版本号，没有版本状态持久化，无法判断是否需要重新构建。`projects.yaml` 已有 `version` 字段但未被脚本层消费，`project-resolver.sh` 也未解析该字段。

本项目采用 AI 层 + 脚本层分工模型：所有"分析"和"决策"由 AI 层完成，脚本层只接受参数并执行。因此版本决策逻辑属于 AI 层职责，脚本层只需正确接收和使用 `--version` 参数。

## Goals / Non-Goals

**Goals:**
- `projects.yaml` 成为版本状态的单一事实来源（version + built_commit）
- AI 层在构建前通过 git diff 判断是否有变更，决定版本号
- 每次构建产生唯一且递增的 semver 版本号
- 构建成功后自动回写 `projects.yaml`

**Non-Goals:**
- 不在脚本层实现版本决策逻辑
- 不实现 major/minor 级别的自动 bump（仅 patch 自动递增）
- 不实现 Harbor API 查询（通过 built_commit 对比即可判断）
- 不实现 pre-release / build metadata 等 semver 扩展

## Decisions

### 1. 版本状态存储在 projects.yaml 而非独立文件

在 `projects.yaml` 中增加 `built_commit` 字段，与 `version` 并列。所有构建状态集中管理，不引入额外文件。

替代方案：独立 `build-state.yaml` 可以做到关注点分离，但对于当前单项目场景，额外文件增加了维护成本，且与"yaml 是结果记录"的定位不符。

### 2. 变更检测基于 git commit hash 对比而非文件 hash

使用 `git rev-parse HEAD` 获取当前 commit，与 `built_commit` 对比。相同则视为无变更，不同则视为有变更。

不做细粒度的 `git diff` 路径过滤 — commit 变了就是变了，即使只改了 README。原因：避免维护白名单/黑名单的复杂度。用户触发构建时已有明确意图，commit 级别的对比足以作为"是否有新内容"的信号。

### 3. 版本决策由 AI 层完成，脚本层只接收 --version

符合项目既有的职责分层原则。`build.sh` 的 `--version` 参数已存在，只需确保 resolver 正确读取 yaml 中的 `version` 字段作为 fallback，并移除时间戳 fallback。

### 4. built_commit 为 null 视为首次构建

当 `built_commit` 为空或 `null` 时，AI 层视为首次构建，直接使用当前 `version` 值构建，不做 diff。

## Risks / Trade-offs

- **[yaml 回写时机]** 构建在远端执行，本地需等远端成功后才回写。如果远端构建成功但 SSH 连接断开导致本地未收到成功信号，yaml 不会更新 → 下次构建会重复 bump。缓解：这种情况可通过 Harbor 上的实际 tag 人工核对。
- **[commit 粒度过粗]** 改了 README 也会触发 bump + 构建。缓解：这是有意为之的简化，避免维护路径过滤规则。用户触发构建即表示有构建意图。
- **[并发构建]** 多人同时构建同一项目可能导致 yaml 竞争写入。缓解：当前为单人使用场景，暂不处理。
