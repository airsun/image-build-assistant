## Context

当前 image-build-assistant 的流程止步于镜像推送到 Harbor。对于 k8s 部署场景，运维人员需要手工编写 YAML、登录 kubectl-ready 主机、逐一 apply。此过程重复且容易出错。

项目的部署信息分散在多个来源：开发者了解运行依赖，构建阶段确定镜像地址，运维人员掌握集群拓扑。这些信息在不同时间产生，需要一个积累机制。

现有系统已有成熟的远程执行通道（SSH + SCP），可以复用。AI 层已承担 "分析 + 决策 + 传参" 的角色，部署环节需要升级为 "分析 + 决策 + 编写 YAML + 传参"。

## Goals / Non-Goals

**Goals:**

- 在 `projects.yaml` 中声明项目的 k8s 部署意图，保持索引精简
- 提供 deploy note 机制，支持多角色（开发者、构建者、运维）分阶段积累部署信息
- 定义全局部署规约，让 AI 基于"规约 + 例外描述"生成 YAML，减少描述负担
- AI 生成完整的 k8s YAML 清单，输出到本地版本化目录
- 将 YAML + 自包含的部署摘要推送到远端 deploy host
- Phase 1 交付到人工审核环节，不自动执行 kubectl apply

**Non-Goals:**

- 不自动执行 kubectl apply（Phase 2 范畴）
- 不在远端获取集群信息反馈给 AI（Phase 2 安全脚本）
- 不侵入项目源码，不要求项目配合提供 k8s 配置
- 不实现 Helm / Kustomize 集成
- 不处理 Secret 的实际值管理（只生成骨架，运维手动填写）
- 不实现多集群切换逻辑（仅通过 cluster 字段预留）

## Decisions

### D1: deploy note 与 projects.yaml 分离

projects.yaml 保持索引角色，只存放结构化的最小必要字段（intent、namespace、cluster、domain、container_port、状态回写字段）。项目的详细部署描述放在 `image-builder/projects/{name}.md`，以自然语言条目化书写，不要求严格 schema。

**理由**：部署描述会随时间膨胀（多角色追加内容），放在 projects.yaml 会破坏其索引的可读性和稳定性。独立 md 文件支持自由格式，降低维护门槛。

**备选方案**：deploy-spec.yaml 结构化描述 → 弃选，因为 schema 维护成本高，且限制了自然语言表达的灵活性。

### D2: 规约优先，例外描述

新增 `deploy-conventions.md` 定义全局默认行为（Ingress 暴露、Deployment 1 replica、默认 resource limits 等）。项目的 deploy note 只描述与规约不同的部分。AI 的工作 = 规约默认值 + 项目例外 → 完整 YAML。

**理由**：80% 的部署配置可以被规约覆盖，每个项目只需描述特殊需求，大幅减少重复。规约文档同时服务于 AI（生成参考）和人（理解默认行为）。

**备选方案**：每个项目完整描述所有配置 → 弃选，冗余且容易不一致。

### D3: 双层 note 机制

- **源头 note**（`projects/{name}.md`）：持续积累，跨版本，记录项目部署需求全貌
- **快照 note**（`deploys/{project}/{version}/deploy-note.md`）：随本次 YAML 生成，自包含说明本次生成了什么资源、需要人工处理什么、apply 命令

快照 note 跟随 YAML 一起推送到远端 deploy host，运维人员打开目录即可获得完整信息。

**理由**：源头 note 是活文档，会持续更新；但远端运维人员需要的是本次部署的确定性摘要，不应依赖外部文件。

### D4: remote.env 扩展复用

在 remote.env 中增加 Deploy Host section（DEPLOY_HOST、DEPLOY_PORT、DEPLOY_USER 等），与 Build Host section 并列。如果 build host 和 deploy host 是同一台机器，配置相同即可。

**理由**：复用已有的 SSH 通道机制，不引入新的连接方式。分 section 保持语义清晰。

**备选方案**：独立 deploy.env → 弃选，增加文件数量且 SSH 基础配置有重复。

### D5: YAML 输出按 project/version 版本化存放

本地 `image-builder/deploys/{project}/{version}/` 目录存放 AI 生成的 YAML，文件名带数字前缀表示 apply 顺序（如 `00-namespace.yaml`、`03-deployment.yaml`）。

**理由**：版本化存放支持审计回溯和快速回滚（apply 上一版本的 YAML）。数字前缀让 apply 顺序一目了然。

### D6: deploy.sh Phase 1 职责极简

Phase 1 的 deploy.sh 只做：读取 projects.yaml deploy 配置 → 接收 AI 生成的 YAML 目录路径 → SCP 推送到远端 deploy host 指定位置。不执行 kubectl，不做集群交互。

**理由**：Phase 1 的安全边界是"生成 + 推送 + 人工审核"。执行权完全交给运维人员。

## Risks / Trade-offs

- **AI 生成 YAML 质量风险** → Phase 1 依赖人工审核兜底；规约文档约束 AI 的自由发挥空间；后续可加 kubeconform 静态校验
- **deploy note 自然语言歧义** → AI 理解不准确时生成错误配置 → 人工审核是安全网；积累使用经验后可逐步收紧 note 的书写指南
- **规约文档滞后于集群实际配置** → 运维人员在审核时发现不一致后更新规约 → 规约是活文档
- **deploys/ 目录膨胀** → 版本化存放会累积大量历史 YAML → 可定期清理旧版本，或在 .gitignore 中排除
- **Secret 管理空白** → Phase 1 只生成骨架，实际值由运维填写 → Phase 2 可考虑集成 External Secrets 或 Sealed Secrets
