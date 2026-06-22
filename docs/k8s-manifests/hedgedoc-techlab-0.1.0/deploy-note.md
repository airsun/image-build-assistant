# HedgeDoc（techlab）— 手工 apply 前说明

## 构建状态（截至生成时）

skytech 组构建在远端 **未成功**：`yarn install` 阶段 **`better-sqlite3` 在 Alpine 镜像内 native build 失败**。需先在 `vibe-hedgedoc` 仓库调整 Dockerfile（例如在 `yarn install` 前 `apk add python3 make g++`，或收窄 workspace 依赖避免拉取需编译的 sqlite），再重新 `build.sh --group hedgedoc --env skytech`。

镜像地址按当前 Harbor 与 `projects.yaml` 约定（构建成功后）：

- `harbor.tech.skytech.io/ai.infra/vibe-hedgedoc-backend:0.1.0`
- `harbor.tech.skytech.io/ai.infra/vibe-hedgedoc-frontend:0.1.0`

## 待你确认 / 填写

| 项 | 草案 | 请你定稿 |
|----|------|----------|
| Ingress 域名 | `hedgedoc.example.tech` | 实际 DNS / 证书策略 |
| 路径分流 | `/` → 前端，`/api` → 后端（常见） | 是否与集群现有 Ingress Controller、HedgeDoc 实际路由一致 |
| PostgreSQL | 未包含 StatefulSet；用 Secret 接**已有**库 | host/port/db/user/password |
| `HD_AUTH_SESSION_SECRET` | Secret 占位 | 强随机串 |
| uploads 持久化 | 含 PVC + backend volumeMount | 容量、StorageClass；若不要持久化可删 PVC 并改配置 |

## Apply 顺序建议

若 `techlab` 已存在，**跳过** `00-namespace.yaml`（或改为只打 label，勿重复创建）。

```bash
# kubectl apply -f 00-namespace.yaml   # 仅当 techlab 尚不存在时
kubectl apply -f 01-configmap.yaml
kubectl apply -f 02-secret.yaml
kubectl apply -f 03-pvc-uploads.yaml
kubectl apply -f 04-deployment-backend.yaml
kubectl apply -f 05-service-backend.yaml
kubectl apply -f 06-deployment-frontend.yaml
kubectl apply -f 07-service-frontend.yaml
kubectl apply -f 08-ingress.yaml
```

验证：`kubectl -n techlab rollout status deploy/vibe-hedgedoc-backend`（及 frontend）。
