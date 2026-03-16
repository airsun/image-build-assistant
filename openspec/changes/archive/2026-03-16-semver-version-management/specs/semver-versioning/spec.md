## ADDED Requirements

### Requirement: projects.yaml 记录 built_commit
`projects.yaml` 中每个项目条目 SHALL 支持 `built_commit` 字段，记录该版本镜像对应的源码 commit short hash。字段值为字符串或 null。

#### Scenario: 首次注册项目
- **WHEN** 项目首次添加到 `projects.yaml` 且未执行过构建
- **THEN** `built_commit` 字段 SHALL 为 null 或不存在

#### Scenario: 构建成功后回写
- **WHEN** 镜像构建并推送成功
- **THEN** `built_commit` SHALL 更新为构建时源码仓库 HEAD 的 short commit hash
- **AND** `version` SHALL 更新为本次构建使用的版本号

### Requirement: project-resolver 解析 version 和 built_commit
`project-resolver.sh` 的 `resolve_project_by_name` 函数 SHALL 从 `projects.yaml` 中解析 `version` 和 `built_commit` 字段，使其可用于后续构建流程。

#### Scenario: 解析包含版本信息的项目
- **WHEN** `projects.yaml` 中的项目条目包含 `version: 1.0.0` 和 `built_commit: abc123f`
- **THEN** resolver SHALL 将 `VERSION` 设置为 `1.0.0`，`BUILT_COMMIT` 设置为 `abc123f`

#### Scenario: 解析缺少版本信息的项目
- **WHEN** `projects.yaml` 中的项目条目缺少 `version` 或 `built_commit` 字段
- **THEN** resolver SHALL 将对应变量设置为空字符串

### Requirement: 构建版本号只能前进
构建使用的版本号 MUST 严格大于 `projects.yaml` 中记录的当前 `version`。

#### Scenario: 自动 bump patch
- **WHEN** AI 层决定自动 bump 版本
- **THEN** 版本号 SHALL 在当前 patch 位 +1（如 1.0.0 → 1.0.1）

#### Scenario: 用户指定合法版本
- **WHEN** 用户指定的目标版本号严格大于当前版本
- **THEN** SHALL 使用用户指定的版本号

#### Scenario: 用户指定非法版本
- **WHEN** 用户指定的目标版本号小于或等于当前版本
- **THEN** SHALL 拒绝构建并提示"版本不能倒退，当前为 X.Y.Z"

### Requirement: commit 未变时默认不构建
当源码仓库 HEAD commit 与 `built_commit` 相同时，系统 SHALL 默认不执行构建。

#### Scenario: commit 未变且用户未坚持
- **WHEN** HEAD commit 等于 `built_commit`
- **AND** 用户未明确要求强制构建
- **THEN** SHALL 告知用户"镜像已是最新（commit: xxx）"并终止构建流程

#### Scenario: commit 未变但用户坚持构建
- **WHEN** HEAD commit 等于 `built_commit`
- **AND** 用户明确要求构建
- **THEN** SHALL bump patch 版本号并执行构建

#### Scenario: 首次构建
- **WHEN** `built_commit` 为 null 或为空
- **THEN** SHALL 视为有变更，使用当前 `version` 值执行构建

### Requirement: build.sh 移除时间戳 fallback
`build.sh` 的版本解析逻辑 SHALL 不再使用时间戳作为 fallback。版本号 MUST 来自 `--version` 参数或 `projects.yaml` 中的 `version` 字段。

#### Scenario: 未提供 --version 参数
- **WHEN** 调用 `build.sh` 时未传 `--version`
- **THEN** SHALL 使用 `projects.yaml` 中的 `version` 字段值

#### Scenario: 提供 --version 参数
- **WHEN** 调用 `build.sh` 时传入 `--version 1.2.0`
- **THEN** SHALL 使用 `1.2.0` 作为镜像 tag
