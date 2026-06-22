---
name: k8s-cluster-snapshot
description: >-
  Runs image-build-assistant read-only kubectl inventory (JSON): current context,
  API server URL, namespace phases, and Ingress summaries (hosts, class, LB).
  Use when creating or clarifying K8s deploy fields in projects.yaml, writing
  deploy notes, aligning deploy.cluster with kubectl context, listing ingress
  or domains for a namespace (e.g. techlab), or when the user asks for cluster
  facts, ingress list, namespace inventory, or live cluster state instead of
  guessing. Requires kubectl and valid credentials in the execution environment
  (local machine, CI, or SSH session on a jump/deploy host).
---

# K8s cluster snapshot（只读盘点）

## 何时使用

在 **image-build-assistant** 仓库中，凡属于下列情形，**优先**执行本 Skill 所指的脚本，用机器可读事实支撑澄清与登记，**不要**默认让用户去控制台逐项查：

- 新建或修改 `projects.yaml` 的 `deploy`（`namespace`、`domain`、`cluster`、`container_port` 以外的**集群侧事实**）
- 编写或核对 `image-builder/projects/{name}.md`（deploy note）里与 Ingress / 域名 / 命名空间相关的描述
- 用户自然语言：**集群现状**、**ingress**、**有哪些域名**、**techlab 里有什么**、**当前 context**、**和 projects 里 cluster 字段对不对**
- 多服务部署（如 HedgeDoc）需要对照**已有** Ingress / 路径习惯时

若当前会话**无法**执行 `kubectl`（无 CLI、无 kubeconfig、沙箱无网络）：向用户说明缺口；请其在已登录集群的环境运行同一命令并把 **JSON 摘要或文件**贴回，或改用 SSH 到跳板/部署机再执行。

## 怎么做

1. **工作目录**：本仓库根目录（或能解析到 `image-builder/scripts/` 的路径）。
2. **执行**（stdout 即 JSON）：

   ```bash
   bash image-builder/scripts/k8s-readonly-inventory.sh
   ```

   仅关注某一命名空间下的 Ingress（例如 `techlab`）：

   ```bash
   bash image-builder/scripts/k8s-readonly-inventory.sh -n techlab
   ```

   写入文件便于粘贴或存档：

   ```bash
   bash image-builder/scripts/k8s-readonly-inventory.sh -n techlab -o /tmp/k8s-snapshot.json
   ```

3. **环境变量**：标准 `KUBECONFIG`；单集群场景下使用当前 context 即可。

4. **用产出做什么**（示例）：

   - `cluster.current_context` → 与 `projects.yaml` 中 `deploy.cluster` **对齐或记录差异**（团队约定以 context 名为准时）
   - `cluster.api_server` → 记录环境指纹，避免连错集群
   - `ingresses`（可按 namespace 过滤后）→ 推断**已有** `host`、IngressClass、是否与 `dan-flow-hub` 等同域体系
   - `namespaces` → 确认 `namespace` 将部署到的空间是否存在、phase 是否正常

5. **呈现给用户**：条目多时用**摘要表**（context、API server、目标 ns 下 ingress 的 host/name）；不必全文粘贴大 JSON，除非用户要存档。

6. **安全**：脚本**不**输出 kubeconfig 密钥；仍勿把含内网地址的 JSON 提交到公开仓库。

## 与仓库文档的关系

- 字段说明与扩展方式：[docs/k8s-readonly-inventory.md](../../../docs/k8s-readonly-inventory.md)
- 主协调流程（何时在部署前跑盘点）：[CLAUDE.md](../../../CLAUDE.md)「集群事实采集」
- Cursor 全局执行策略：[execution.mdc](../../rules/execution.mdc)「K8s 部署澄清与盘点」

## 自然语言映射（便于触发）

用户若说类似以下内容，应按本 Skill 处理：**拉一下集群信息**、**看看 techlab ingress**、**当前 k8s context**、**别让我自己去控制台查**、**生成部署配置前先确认集群里有什么**。
