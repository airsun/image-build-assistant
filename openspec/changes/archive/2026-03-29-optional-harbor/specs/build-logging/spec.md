## MODIFIED Requirements

### Requirement: Build log auto-capture
构建脚本执行时 SHALL 自动将完整输出（stdout + stderr）写入 `logs/{project-name}/{timestamp}.log`，同时保持终端实时输出。日志中的镜像名 SHALL 反映实际 tag：有 Harbor 时为完整 Harbor 路径，无 Harbor 时为纯 `IMAGE_NAME:VERSION`。

#### Scenario: Successful build creates log file
- **WHEN** `build.sh --project claude-code-hub --config remote-envs/skytech.env` 执行成功
- **THEN** `logs/claude-code-hub/{timestamp}.log` 文件被创建，包含完整的构建输出，镜像 tag 为 `harbor.xxx/project/claude-code-hub:version`

#### Scenario: Build without Harbor creates log with simple tag
- **WHEN** `build.sh --project my-app --config remote-envs/home-134.env` 执行成功，且 home-134.env 中 HARBOR_HOST 为空
- **THEN** `logs/my-app/{timestamp}.log` 文件被创建，镜像 tag 为 `my-app:version`

#### Scenario: Failed build also creates log file
- **WHEN** `build.sh --project claude-code-hub` 执行失败（远端构建错误）
- **THEN** `logs/claude-code-hub/{timestamp}.log` 文件被创建，包含到失败点为止的所有输出

#### Scenario: Terminal output preserved
- **WHEN** 构建脚本执行时
- **THEN** 所有输出同时显示在终端（stdout/stderr 不被静默吞掉）
