## ADDED Requirements

### Requirement: Build log auto-capture
构建脚本执行时 SHALL 自动将完整输出（stdout + stderr）写入 `logs/{project-name}/{timestamp}.log`，同时保持终端实时输出。

#### Scenario: Successful build creates log file
- **WHEN** `bin/build-image.sh --project claude-code-hub` 执行成功
- **THEN** `logs/claude-code-hub/{timestamp}.log` 文件被创建，包含完整的构建输出

#### Scenario: Failed build also creates log file
- **WHEN** `bin/build-image.sh --project claude-code-hub` 执行失败（远端构建错误）
- **THEN** `logs/claude-code-hub/{timestamp}.log` 文件被创建，包含到失败点为止的所有输出

#### Scenario: Terminal output preserved
- **WHEN** 构建脚本执行时
- **THEN** 所有输出同时显示在终端（stdout/stderr 不被静默吞掉）

### Requirement: Log directory auto-creation
构建脚本 SHALL 在写入日志前自动创建 `logs/{project-name}/` 目录，无需手动预创建。

#### Scenario: First build for a new project
- **WHEN** 首次构建一个项目，`logs/{project-name}/` 目录尚不存在
- **THEN** 脚本自动创建该目录并写入日志

### Requirement: Log filename format
日志文件名 SHALL 使用 `{YYYYMMDD}-{HHMMSS}.log` 格式，确保按时间排序。

#### Scenario: Log filename convention
- **WHEN** 构建在 2026-03-13 14:30:22 执行
- **THEN** 日志文件名为 `20260313-143022.log`

### Requirement: Logs excluded from version control
`logs/` 目录 SHALL 被 `.gitignore` 排除，不纳入版本控制。

#### Scenario: Git status ignores logs
- **WHEN** 构建产生日志文件后执行 `git status`
- **THEN** `logs/` 下的文件不出现在 untracked 列表中
