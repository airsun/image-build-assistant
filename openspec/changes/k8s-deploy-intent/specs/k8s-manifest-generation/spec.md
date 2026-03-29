## ADDED Requirements

### Requirement: AI 生成 k8s YAML 清单的输入

AI 层生成 YAML 前 MUST 读取以下输入：

1. `image-builder/deploy-conventions.md` — 全局规约
2. `image-builder/projects/{name}.md` — 项目 deploy note（如存在）
3. `image-builder/projects.yaml` 中的 deploy section — 结构化关键字段
4. 构建产物信息 — 完整镜像地址（`{HARBOR_HOST}/{harbor_project}/{image_name}:{version}`）

#### Scenario: 输入完整时生成 YAML

- **WHEN** 以上 4 项输入均可获取
- **THEN** AI SHALL 综合所有输入生成完整的 k8s YAML 清单

#### Scenario: deploy note 缺失时降级生成

- **WHEN** 项目无 deploy note 文件但 projects.yaml 有完整 deploy section
- **THEN** AI SHALL 仅基于规约 + projects.yaml 字段生成基础 YAML，并在 deploy-note.md 中标注信息来源有限

### Requirement: YAML 输出目录结构

生成的 YAML SHALL 输出到 `image-builder/deploys/{project}/{version}/` 目录。目录结构：

```
deploys/{project}/{version}/
  00-namespace.yaml          # 如 namespace 需创建
  01-configmap.yaml          # 如需 ConfigMap
  02-secret.yaml             # 如需 Secret（仅骨架）
  03-pvc.yaml                # 如需持久化存储
  04-deployment.yaml         # 核心工作负载
  05-service.yaml            # ClusterIP Service
  06-ingress.yaml            # Ingress 规则
  deploy-note.md             # 本次部署的自包含摘要
```

文件名 MUST 带两位数字前缀，表示推荐的 apply 顺序。不需要的资源类型不生成对应文件。

#### Scenario: 项目只需 Deployment + Service + Ingress

- **WHEN** deploy note 未提及 PVC、ConfigMap、Secret 等额外资源
- **THEN** 输出目录仅包含 `00-namespace.yaml`（如需）、`04-deployment.yaml`、`05-service.yaml`、`06-ingress.yaml`、`deploy-note.md`

#### Scenario: 项目需要完整资源组合

- **WHEN** deploy note 描述了 PVC、ConfigMap 和 Secret 需求
- **THEN** 输出目录包含对应的所有 YAML 文件，每个文件的 metadata.namespace 与 projects.yaml 的 deploy.namespace 一致

### Requirement: deploy-note.md 快照文件

每次生成 MUST 同时输出 `deploy-note.md`，内容 SHALL 包含：

- 镜像地址和版本
- 本次生成的资源清单（文件名 + 资源类型 + 简要说明）
- 需要人工处理的事项（如填写 Secret 值、确认 DNS 等）
- 按顺序的 kubectl apply 命令
- 基本的验证命令（rollout status、get pods 等）

deploy-note.md SHALL 自包含，运维人员仅凭此文件即可理解并执行部署。

#### Scenario: 运维人员在远端查看部署摘要

- **WHEN** YAML 和 deploy-note.md 推送到远端 deploy host
- **THEN** 运维人员打开 deploy-note.md 即可获得本次部署的完整信息，无需查阅其他文件

#### Scenario: 存在需要人工填写的 Secret

- **WHEN** 生成的 YAML 包含 Secret 骨架（data 字段为占位符）
- **THEN** deploy-note.md 的人工处理事项中 MUST 列出需要填写的 Secret key 及其用途

### Requirement: YAML 内容质量约束

AI 生成的 YAML MUST 满足：

- apiVersion 使用当前稳定版本（apps/v1、networking.k8s.io/v1 等）
- 所有资源的 metadata.namespace 与 deploy.namespace 一致
- Deployment 的 image 字段使用完整镜像地址（含 registry、project、tag）
- resource requests/limits 必须显式设置
- label selector 在 Deployment 和 Service 之间保持一致
- Ingress 的 host 与 deploy.domain 一致

#### Scenario: YAML 格式校验

- **WHEN** AI 生成 YAML 后
- **THEN** 每个 YAML 文件 SHALL 是合法的 YAML 格式且包含完整的 apiVersion、kind、metadata 字段

### Requirement: 版本化存放与历史保留

`deploys/{project}/` 下按版本子目录存放，不同版本的 YAML 互不覆盖。用于支持审计回溯和快速回滚。

#### Scenario: 同一项目多次部署

- **WHEN** 项目先后生成 v-0.6.7 和 v-0.6.8 的 YAML
- **THEN** `deploys/{project}/v-0.6.7/` 和 `deploys/{project}/v-0.6.8/` 均保留完整内容
