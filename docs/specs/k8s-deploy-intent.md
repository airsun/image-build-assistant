# K8s 部署意图规范

镜像构建推送到 Harbor 后，对于声明了 k8s 部署意图的项目，AI 层基于全局规约 + 项目 deploy note + 构建产物信息生成 k8s YAML 清单，推送到远端 deploy host 供人工审核后 apply。Phase 1 交付到人工审核，不自动执行。

## 1. 部署意图声明（deploy-intent）

### projects.yaml deploy section

每个项目条目支持可选的 `deploy` section：

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `intent` | string | 是 | `k8s` 或 `none`（默认 `none`） |
| `namespace` | string | intent=k8s 时必填 | 目标 k8s namespace |
| `cluster` | string | 否 | 集群标识，默认 `default`，多集群预留 |
| `domain` | string | 否 | Ingress 域名 |
| `container_port` | integer | intent=k8s 时必填 | 容器监听端口 |
| `deployed_version` | string | 否 | 上次成功部署的版本，由系统回写 |
| `deployed_commit` | string | 否 | 上次部署对应的 commit hash，由系统回写 |

未声明 `deploy` section 的项目等同于 `intent: none`，不触发部署流程。

### deploy note 文件

`image-builder/projects/{project-name}.md` 为每个有部署意图的项目维护 deploy note：

- 自然语言条目化格式，不要求严格 schema
- 覆盖：运行依赖、存储需求、配置注入、资源需求、运维补充
- 支持多角色（开发者、构建者、运维）分阶段追加
- AI 生成 YAML 时必须读取；不存在时基于已知信息降级生成

### project-resolver 扩展

`project-resolver.sh` 解析 deploy section 字段（DEPLOY_INTENT、DEPLOY_NAMESPACE、DEPLOY_CLUSTER、DEPLOY_DOMAIN、DEPLOY_CONTAINER_PORT、DEPLOYED_VERSION、DEPLOYED_COMMIT），兼容无 deploy section 的旧项目。

## 2. 全局部署规约（deploy-conventions）

`image-builder/deploy-conventions.md` 定义所有 k8s 部署项目的默认行为，同时服务 AI（生成参考）和人（理解默认行为）：

- **网络访问**：默认 Ingress + 域名暴露，ClusterIP Service，不用 NodePort/LoadBalancer
- **工作负载**：默认 Deployment，replicas 1，默认 resource requests/limits 有合理预设
- **镜像拉取**：`{HARBOR_HOST}/{harbor_project}/{image_name}:{version}`，imagePullSecrets 集群全局配置
- **Namespace**：不存在则生成创建用 YAML
- **存储**：默认无持久化，需要时 deploy note 说明，使用集群默认 StorageClass
- **配置注入**：默认无额外配置，ConfigMap/Secret 由 deploy note 说明，Secret 只生成骨架

项目 deploy note 中的描述覆盖规约默认值。

## 3. YAML 清单生成（k8s-manifest-generation）

### 输入

1. `deploy-conventions.md` — 全局规约
2. `projects/{name}.md` — 项目 deploy note（如存在）
3. `projects.yaml` deploy section — 结构化关键字段
4. 构建产物信息 — 完整镜像地址

### 输出目录

```
image-builder/deploys/{project}/{version}/
  00-namespace.yaml          # 如需创建
  01-configmap.yaml          # 如需
  02-secret.yaml             # 如需（仅骨架）
  03-pvc.yaml                # 如需
  04-deployment.yaml         # 核心
  05-service.yaml            # ClusterIP
  06-ingress.yaml            # Ingress
  deploy-note.md             # 自包含部署摘要
```

数字前缀表示 apply 顺序，不需要的资源不生成。按 project/version 版本化存放，支持审计回溯。

### deploy-note.md 快照

每次生成同时输出 deploy-note.md：

- 镜像地址和版本
- 资源清单（文件名 + 类型 + 说明）
- 需人工处理事项（填 Secret 值、确认 DNS 等）
- kubectl apply 命令（按顺序）
- 验证命令（rollout status、get pods）

自包含，运维人员仅凭此文件即可执行部署。

### YAML 质量约束

- apiVersion 使用稳定版本（apps/v1、networking.k8s.io/v1 等）
- metadata.namespace 与 deploy.namespace 一致
- image 字段使用完整镜像地址
- resource requests/limits 显式设置
- label selector 在 Deployment 和 Service 间一致
- Ingress host 与 deploy.domain 一致

## 4. 远端推送（deploy-remote-push）

### remote.env 扩展

新增 Deploy Host section：

| 字段 | 必填 | 默认值 | 说明 |
|------|------|--------|------|
| `DEPLOY_HOST` | 是 | — | deploy host 地址，可与 REMOTE_HOST 相同 |
| `DEPLOY_PORT` | 否 | 22 | SSH 端口 |
| `DEPLOY_USER` | 是 | — | SSH 用户 |
| `DEPLOY_SSH_KEY_PATH` | 是 | — | SSH 私钥路径 |
| `DEPLOY_BASE_DIR` | 是 | — | 远端 YAML 存放根目录 |

### deploy.sh 入口

参数：`--project`（必填）、`--deploy-dir`（必填）、`--config`、`--projects`

职责（Phase 1）：读取配置 → 接收 YAML 目录 → SCP 推送到远端 `{DEPLOY_BASE_DIR}/{project}/{version}/` → 输出远端路径。远端目录已存在时提示是否覆盖。

### 远端目录结构

```
{DEPLOY_BASE_DIR}/{project}/{version}/
  *.yaml
  deploy-note.md
```

运维人员在远端目录中审核并 apply。
