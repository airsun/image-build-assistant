## MODIFIED Requirements

### Requirement: 构建版本号只能前进
构建使用的版本号 MUST 严格大于 `projects.yaml` 中记录的当前 `version`。

AI 层在执行版本决策后、调用 `build.sh` 时，SHALL 先完成环境路由（解析项目 `env` 字段为 config 路径），再将 `--config` 与 `--version`、`--project` 一并传给 `build.sh`。

#### Scenario: 自动 bump patch
- **WHEN** AI 层决定自动 bump 版本
- **THEN** 版本号 SHALL 在当前 patch 位 +1（如 1.0.0 → 1.0.1）

#### Scenario: 用户指定合法版本
- **WHEN** 用户指定的目标版本号严格大于当前版本
- **THEN** SHALL 使用用户指定的版本号

#### Scenario: 用户指定非法版本
- **WHEN** 用户指定的目标版本号小于或等于当前版本
- **THEN** SHALL 拒绝构建并提示"版本不能倒退，当前为 X.Y.Z"

#### Scenario: 带环境路由的构建调用
- **WHEN** AI 层构建项目 `hub-neo`（env: skytech），版本决策为 `v-0.6.8`
- **THEN** AI 层 SHALL 调用 `build.sh --config image-builder/remote-envs/skytech.env --project hub-neo --version v-0.6.8`
