## Why

镜像构建推送到 Harbor 后，缺少从"镜像可用"到"服务运行"的衔接。对于 k8s 部署意图的项目，需要一条路径：AI 基于项目部署描述和全局规约生成 k8s YAML 清单，输出到指定位置供人工审核后 apply。当前迭代（Phase 1）聚焦在 YAML 生成与人工审核，不自动执行。

## What Changes

- `projects.yaml` 新增 `deploy` section：`intent`、`namespace`、`cluster`、`domain`、`container_port`、`deployed_version`、`deployed_commit` 等索引级字段
- 新增 `image-builder/projects/` 目录，按项目维护 deploy note（自然语言条目化描述），记录来自开发者、构建者、运维的部署信息
- 新增 `image-builder/deploy-conventions.md`，定义全局部署规约（默认 Ingress 暴露、默认 Deployment、默认 resource limits 等），AI 生成 YAML 的基础参考
- 新增 `image-builder/deploys/{project}/{version}/` 输出目录，存放 AI 生成的 k8s YAML 清单 + deploy-note.md（本次部署的自包含摘要）
- `remote.env` 扩展 Deploy Host section（可复用 build host），支持将生成的 YAML 推送到远端 kubectl-ready 主机
- 新增 `deploy.sh` 作为部署流程入口，Phase 1 职责：读取配置 → 传递 AI 生成的 YAML → SCP 推送到远端
- AI 层角色升级：读取规约 + deploy note + 构建产物信息 → 生成完整 k8s manifest 清单

## Capabilities

### New Capabilities
- `deploy-intent`: 项目部署意图声明与配置管理，包括 projects.yaml 的 deploy section 扩展和 deploy note 机制
- `deploy-conventions`: 全局 k8s 部署规约定义，作为 AI 生成 YAML 的默认规则基础
- `k8s-manifest-generation`: AI 基于规约 + 项目 deploy note + 构建产物信息生成 k8s YAML 清单的流程规范
- `deploy-remote-push`: 将生成的 YAML 清单推送到远端 deploy host 的执行通道

### Modified Capabilities

## Impact

- `image-builder/projects.yaml`：每个项目条目新增 deploy section
- `image-builder/remote.env`：新增 Deploy Host 配置段
- `image-builder/scripts/project-resolver.sh`：需解析新增的 deploy 字段
- 新增文件：`deploy-conventions.md`、`deploy.sh`、`projects/*.md`、`deploys/` 输出目录
- 新增远端脚本：`scripts/remote-deploy-entry.sh`（Phase 1 可能很薄，主要做文件接收）
- AI 层（Claude Code）工作流扩展：构建完成后检测 deploy intent，进入部署 YAML 生成流程
