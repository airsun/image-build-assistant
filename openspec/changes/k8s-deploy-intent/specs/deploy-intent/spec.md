## ADDED Requirements

### Requirement: projects.yaml deploy section 声明

每个项目条目 SHALL 支持可选的 `deploy` section，包含以下字段：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `intent` | string | 是 | 部署意图，取值 `k8s` 或 `none`（默认 `none`） |
| `namespace` | string | intent=k8s 时必填 | 目标 k8s namespace |
| `cluster` | string | 否 | 集群标识，默认 `default`，多集群预留 |
| `domain` | string | 否 | Ingress 域名 |
| `container_port` | integer | intent=k8s 时必填 | 容器监听端口 |
| `deployed_version` | string | 否 | 上次成功部署的版本，由系统回写 |
| `deployed_commit` | string | 否 | 上次部署对应的 commit hash，由系统回写 |

未声明 `deploy` section 的项目等同于 `intent: none`。

#### Scenario: 已有项目新增 deploy 配置

- **WHEN** 运维人员为已注册的构建项目添加 `deploy` section 且 `intent: k8s`
- **THEN** 系统能正确解析 deploy 字段，在部署流程中使用

#### Scenario: 无 deploy section 的项目

- **WHEN** 项目条目未包含 `deploy` section
- **THEN** 系统视为 `intent: none`，不触发任何部署相关流程

#### Scenario: 部署成功后回写状态

- **WHEN** 部署 YAML 生成并推送成功
- **THEN** 系统 SHALL 回写 `deployed_version` 和 `deployed_commit` 到 projects.yaml

### Requirement: deploy note 文件管理

系统 SHALL 在 `image-builder/projects/` 目录下为每个有部署意图的项目维护一个 deploy note 文件，命名为 `{project-name}.md`。

deploy note 为自然语言条目化格式，不要求严格 schema。内容 SHALL 覆盖项目部署所需的关键信息，包括但不限于：运行依赖、存储需求、配置注入、资源需求、运维补充说明。

deploy note 支持多角色（开发者、构建者、运维人员）在不同时间追加内容。

#### Scenario: AI 读取 deploy note 生成 YAML

- **WHEN** AI 层进入部署 YAML 生成流程
- **THEN** AI MUST 读取 `image-builder/projects/{project-name}.md` 作为生成输入之一

#### Scenario: deploy note 不存在

- **WHEN** 项目声明了 `deploy.intent: k8s` 但 `projects/{name}.md` 不存在
- **THEN** AI SHALL 提示用户创建 deploy note 或基于已知信息（projects.yaml 字段 + 构建信息）尝试生成基础 YAML，并在输出中标注信息不完整

### Requirement: project-resolver 扩展

`project-resolver.sh` SHALL 支持解析 `deploy` section 下的所有字段，供 `deploy.sh` 和 AI 层使用。解析逻辑 MUST 兼容无 deploy section 的旧项目条目。

#### Scenario: 解析含 deploy section 的项目

- **WHEN** `resolve_project_by_name` 处理含 `deploy` section 的项目
- **THEN** deploy 相关字段（DEPLOY_INTENT、DEPLOY_NAMESPACE、DEPLOY_CLUSTER、DEPLOY_DOMAIN、DEPLOY_CONTAINER_PORT、DEPLOYED_VERSION、DEPLOYED_COMMIT）SHALL 被正确赋值

#### Scenario: 解析不含 deploy section 的项目

- **WHEN** `resolve_project_by_name` 处理不含 `deploy` section 的项目
- **THEN** DEPLOY_INTENT SHALL 为空字符串，其余 deploy 字段为空，不影响构建流程
