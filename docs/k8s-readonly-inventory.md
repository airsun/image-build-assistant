# K8s 只读盘点（单集群）

目标：**环境已能 `kubectl` 连上集群时**，由脚本一次性产出结构化 JSON，供自动化或 AI 消费，避免人手从控制台/零散命令里「搬运」集群事实（context、API 地址、Ingress、命名空间等）。

## 使用方式

在已配置 `kubectl` 的机器上（`KUBECONFIG` 或默认 `~/.kube/config` 指向目标单集群）：

```bash
bash image-builder/scripts/k8s-readonly-inventory.sh
bash image-builder/scripts/k8s-readonly-inventory.sh -n techlab
bash image-builder/scripts/k8s-readonly-inventory.sh -o /tmp/cluster-snapshot.json
```

- **不写 kubeconfig 密钥**：输出里只有 `api_server` URL、context 名、资源摘要，不含 client 证书或 token。
- **`-n`**：Ingress 仅列该 namespace；`namespaces` 仍为全集群列表（便于对照）。

## 在远端机器上跑（与 `remote.env` 的关系）

**本脚本不读取** `image-builder/remote.env` 或 `remote-envs/*.env`：它只调用当前环境中的 `kubectl`（`KUBECONFIG` 或默认 `~/.kube/config`）。

若本机没有集群凭据、但有一台已能 `kubectl` 的机器（常见做法：与 **`DEPLOY_*` 同一台**，即放清单、也能连 API 的运维机；或单独跳板机）：

1. 在该机器上安装 `kubectl` + 配置好 kubeconfig（只读 ServiceAccount 即可）。
2. 从本仓库所在机器 **SSH 上去执行**，复用环境文件里已有的部署机变量（示例，先 `source` 你的 `skytech.env`）：

   ```bash
   # 已 source image-builder/remote-envs/skytech.env
   scp -i "$DEPLOY_SSH_KEY_PATH" -P "${DEPLOY_PORT}" \
     image-builder/scripts/k8s_readonly_inventory.py \
     image-builder/scripts/k8s-readonly-inventory.sh \
     "${DEPLOY_USER}@${DEPLOY_HOST}:/tmp/"
   ssh -i "$DEPLOY_SSH_KEY_PATH" -p "${DEPLOY_PORT}" "${DEPLOY_USER}@${DEPLOY_HOST}" \
     'bash /tmp/k8s-readonly-inventory.sh -n techlab'
   ```

   也可把本仓库挂在远端同一路径，直接 `bash .../k8s-readonly-inventory.sh`，无需 scp。

3. **模板里目前没有单独的「K8s 盘点主机」变量**；若盘点机与 `DEPLOY_HOST` 不同，可自行在 `remote-envs/*.env` 末尾增加约定变量（如 `KUBECTL_BASTION_HOST`），由你方脚本或 AI 读取——`build.sh` / `deploy.sh` **不会**消费这些键。

## 输出 JSON 约定（可扩展）

| 字段 | 说明 |
|------|------|
| `schema_version` | 整数；增字段时若破坏兼容可递增 |
| `generated_at` | UTC ISO8601 |
| `cluster` | `current_context`、`api_server`、`server_version`（`kubectl version` 中的 server 段，能取到则填） |
| `filter` | 当前使用的 namespace 过滤条件 |
| `namespaces` | `{ name, phase }[]` |
| `ingresses` | `{ namespace, name, ingress_class, hosts, tls_hosts, load_balancer }[]` |
| `sections` | 预留给后续扩展（如 Service、StorageClass），默认为 `{}` |

后续若要加表（例如 `kubectl get svc -n techlab -o json` 的摘要），在 `k8s_readonly_inventory.py` 中增加组装逻辑，并视情况 bump `schema_version`。

## 权限建议（RBAC）

为执行账号绑定**只读** ClusterRole，例如：`get/list` 于 `namespaces`、`ingresses`；`ingresses` 在 `networking.k8s.io` 与扩展版本视集群而定。若仅盘点特定 namespace，可用 Role 限定该 namespace 的 `ingresses`，并保留集群级 `namespaces` 的 `list`（或改为不拉全量 namespaces——可按需在脚本中加开关）。

## 与 image-build-assistant 其它部分的关系

- **独立于** `build.sh` / `deploy.sh`：不修改构建与推送流程。
- 可与 **部署机** 合一：在 `DEPLOY_HOST` 上配置只读 kubeconfig，由 SSH 远程执行本脚本，将 JSON 拉回本地或交给 AI。

## Cursor Skill 与自然语言触发

在 Cursor 中，由项目 Skill **`k8s-cluster-snapshot`**（`.cursor/skills/k8s-cluster-snapshot/SKILL.md`）约定：在创建/澄清 K8s 部署配置或用户索要集群事实时，**应调用本脚本**而非默认人工查询。

- 工作流定义：[CLAUDE.md](../CLAUDE.md)「集群事实采集」、[.cursor/rules/execution.mdc](../.cursor/rules/execution.mdc)「K8s 部署澄清与盘点」
- 用户可用自然语言触发（见 Skill 文末「自然语言映射」）
