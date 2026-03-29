## ADDED Requirements

### Requirement: remote.env Deploy Host 配置

`remote.env` SHALL 新增 Deploy Host section，包含以下字段：

| 字段 | 必填 | 默认值 | 说明 |
|------|------|--------|------|
| `DEPLOY_HOST` | 是 | — | deploy host 地址，可与 REMOTE_HOST 相同 |
| `DEPLOY_PORT` | 否 | 22 | SSH 端口 |
| `DEPLOY_USER` | 是 | — | SSH 用户 |
| `DEPLOY_SSH_KEY_PATH` | 是 | — | SSH 私钥路径 |
| `DEPLOY_BASE_DIR` | 是 | — | 远端 YAML 存放根目录 |

`remote.env.example` MUST 同步更新，包含 Deploy Host section 的示例。

#### Scenario: build host 和 deploy host 是同一台机器

- **WHEN** DEPLOY_HOST 与 REMOTE_HOST 配置为相同地址
- **THEN** 系统正常工作，SSH 通道各自独立建立

#### Scenario: deploy host 配置缺失

- **WHEN** 项目 deploy.intent 为 k8s 但 remote.env 缺少 DEPLOY_HOST
- **THEN** deploy.sh SHALL 报错并提示补全 Deploy Host 配置

### Requirement: deploy.sh 入口脚本

新增 `image-builder/deploy.sh` 作为部署推送入口。Phase 1 职责：

1. 读取 remote.env 的 Deploy Host 配置
2. 读取 projects.yaml 的 deploy section（通过 project-resolver）
3. 接收 `--deploy-dir` 参数指定本地 YAML 目录路径
4. 通过 SCP 将整个目录推送到远端 `{DEPLOY_BASE_DIR}/{project}/{version}/`
5. 输出远端路径，告知用户 YAML 已就位

deploy.sh SHALL 支持以下参数：

| 参数 | 必填 | 说明 |
|------|------|------|
| `--project` | 是 | 项目名 |
| `--deploy-dir` | 是 | 本地 YAML 目录路径 |
| `--config` | 否 | remote.env 路径（默认同 build.sh） |
| `--projects` | 否 | projects.yaml 路径 |

#### Scenario: 正常推送 YAML 到远端

- **WHEN** 运维人员或 AI 层调用 `deploy.sh --project claude-code-hub-neo --deploy-dir deploys/claude-code-hub-neo/v-0.6.7/`
- **THEN** 系统通过 SCP 将目录内容推送到远端 `{DEPLOY_BASE_DIR}/claude-code-hub-neo/v-0.6.7/`
- **AND** 输出远端完整路径

#### Scenario: 远端目录已存在

- **WHEN** 远端目标目录已存在（重复推送同一版本）
- **THEN** 系统 SHALL 提示已存在并询问是否覆盖

### Requirement: 远端目录结构

远端 deploy host 上的目录结构 SHALL 与本地 deploys/ 镜像：

```
{DEPLOY_BASE_DIR}/
  {project}/
    {version}/
      *.yaml
      deploy-note.md
```

运维人员在远端目录中即可完成审核和 apply 操作。

#### Scenario: 运维人员在远端执行部署

- **WHEN** YAML 推送到远端后
- **THEN** 运维人员可进入 `{DEPLOY_BASE_DIR}/{project}/{version}/` 目录，参照 deploy-note.md 执行 kubectl apply
