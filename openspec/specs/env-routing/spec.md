### Requirement: 环境配置目录结构
`image-builder/remote-envs/` 目录 SHALL 存放按环境命名的 `.env` 文件，每个文件包含一个局域网环境的全套远端连接配置。文件名格式为 `{env-name}.env`，`env-name` 使用 kebab-case。

#### Scenario: 多环境配置文件并存
- **WHEN** 存在 `remote-envs/skytech.env` 和 `remote-envs/other-lan.env`
- **THEN** 每份文件 SHALL 各自包含完整的 build host（REMOTE_HOST、REMOTE_PORT、REMOTE_USER、SSH_KEY_PATH、REMOTE_BASE_DIR）、Harbor（HARBOR_HOST、HARBOR_PROJECT，可选）和 deploy host（DEPLOY_HOST、DEPLOY_PORT、DEPLOY_USER、DEPLOY_SSH_KEY_PATH、DEPLOY_BASE_DIR，可选）配置

#### Scenario: env 文件格式与 remote.env.example 一致
- **WHEN** AI 层将 env 文件路径传给 `build.sh --config`
- **THEN** 脚本层 SHALL 能正常 `source` 该文件，无需格式适配

### Requirement: projects.yaml env 字段
`projects.yaml` 中每个项目条目 SHALL 包含顶层 `env` 字段，值为环境名字符串（对应 `remote-envs/{env}.env`）。

#### Scenario: 项目声明环境归属
- **WHEN** 项目条目包含 `env: skytech`
- **THEN** AI 层 SHALL 将构建和部署路由到 `remote-envs/skytech.env` 中定义的基础设施

### Requirement: project-resolver 解析 env 字段
`project-resolver.sh` 的 `resolve_project_by_name` 函数 SHALL 从 `projects.yaml` 中解析 `env` 字段到 `ENV_NAME` 变量。`project_resolver_clear` SHALL 将 `ENV_NAME` 重置为空字符串。

#### Scenario: 解析包含 env 的项目
- **WHEN** `projects.yaml` 中项目条目包含 `env: skytech`
- **THEN** resolver SHALL 将 `ENV_NAME` 设置为 `skytech`

#### Scenario: 解析不含 env 的项目
- **WHEN** `projects.yaml` 中项目条目不含 `env` 字段
- **THEN** resolver SHALL 将 `ENV_NAME` 设置为空字符串

### Requirement: AI 层环境路由
AI 层在调用 `build.sh` 或 `deploy.sh` 前 SHALL 执行环境路由：读取项目的 `env` 字段，解析为 env 文件路径，通过 `--config` 参数传给脚本。

#### Scenario: 路由到 env 文件
- **WHEN** AI 层构建项目，该项目 `env: skytech`
- **THEN** AI 层 SHALL 调用 `build.sh --config image-builder/remote-envs/skytech.env --project <name> --version <ver>`

#### Scenario: env 文件不存在时报错
- **WHEN** AI 层解析到 env 文件路径 `remote-envs/unknown.env` 但文件不存在
- **THEN** AI 层 SHALL 终止操作并提示用户 env 文件不存在，列出 `remote-envs/` 下可用的 env 文件

### Requirement: CLAUDE.md 多环境说明
`CLAUDE.md` SHALL 包含多环境路由的 AI 层行为说明，确保后续 AI 会话能正确执行环境路由。

#### Scenario: AI 层行为文档化
- **WHEN** 新的 AI 会话读取 CLAUDE.md
- **THEN** SHALL 能理解：项目有 `env` 字段时需加载对应 env 文件并传 `--config`
