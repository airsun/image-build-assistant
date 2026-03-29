## MODIFIED Requirements

### Requirement: projects.yaml env 字段
`projects.yaml` 中项目以 `name + env` 为联合唯一键。同一个 `name` 可出现多条记录，每条对应不同的 `env`，各自维护独立的 version、built_commit、harbor_project、deploy 等字段。

#### Scenario: 同名项目多环境记录
- **WHEN** `projects.yaml` 包含两条 `name: hub-neo` 记录，分别 `env: skytech` 和 `env: home-134`
- **THEN** 两条记录 SHALL 各自独立维护 version、built_commit、deploy 等状态字段

#### Scenario: 项目声明环境归属
- **WHEN** 项目条目包含 `env: skytech`
- **THEN** AI 层 SHALL 将构建和部署路由到 `remote-envs/skytech.env` 中定义的基础设施

### Requirement: project-resolver 解析 env 字段
`project-resolver.sh` 的 `resolve_project_by_name` 函数 SHALL 接受可选的第三参数 `env_name`。查找逻辑按 `name + env` 联合匹配。`env_name` 为空时退化为原有 name-only 匹配行为（向后兼容）。

#### Scenario: 按 name + env 精确匹配
- **WHEN** 调用 `resolve_project_by_name registry.yaml hub-neo skytech`
- **AND** registry 中存在 `name: hub-neo, env: skytech` 和 `name: hub-neo, env: home-134`
- **THEN** resolver SHALL 返回 `env: skytech` 对应的记录

#### Scenario: env 不传时按 name 匹配第一条
- **WHEN** 调用 `resolve_project_by_name registry.yaml hub-neo`（不传 env）
- **THEN** resolver SHALL 返回第一条 `name: hub-neo` 的记录（兼容行为）

#### Scenario: name + env 无匹配时报错
- **WHEN** 调用 `resolve_project_by_name registry.yaml hub-neo unknown-env`
- **AND** registry 中不存在 `name: hub-neo, env: unknown-env`
- **THEN** resolver SHALL 报错 "Project not found: hub-neo (env: unknown-env)"

### Requirement: AI 层环境路由
AI 层在调用 `build.sh` 或 `deploy.sh` 前 SHALL 执行环境路由：读取项目的 `env` 字段，解析为 env 文件路径，通过 `--config` 传给脚本，同时通过 `--env` 传给 resolver 做精确匹配。

#### Scenario: 构建多环境项目
- **WHEN** AI 层构建 `hub-neo` 在 skytech 环境
- **THEN** AI 层 SHALL 调用 `build.sh --config remote-envs/skytech.env --project hub-neo --env skytech --version v-0.6.8`

#### Scenario: env 文件不存在时报错
- **WHEN** AI 层解析到 env 文件路径 `remote-envs/unknown.env` 但文件不存在
- **THEN** AI 层 SHALL 终止操作并提示用户 env 文件不存在，列出 `remote-envs/` 下可用的 env 文件
