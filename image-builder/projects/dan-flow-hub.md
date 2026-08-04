# dan-flow-hub 部署说明

## 项目信息

- Web 应用（Python/FastAPI），监听 8000 端口
- 单容器部署
- 镜像：`harbor.tech.skytech.io/ai.infra/dan-flow-hub:{version}`

## 网络暴露

- 通过 Ingress 暴露在 `hub.tech.skytech.io/works/`
- nginx rewrite-target: `/$2`（路径前缀 `/works` 被剥离后转发到后端）
- 内部 ClusterIP Service，port 80 → targetPort 8000

## 运行依赖

- `DATABASE_URL`：数据库连接串（Secret）
- `DANFLOW_CLAUDE_API_KEY`：Claude API 密钥（Secret）

## 配置注入

| Secret Key | 说明 |
|------------|------|
| `DATABASE_URL` | 数据库连接 URL |
| `DANFLOW_CLAUDE_API_KEY` | Anthropic Claude API Key |

部署前需手动填写 Secret 的 data 字段（当前为占位符 `<BASE64_ENCODED_VALUE>`）。

## 存储

- 无持久化存储

## 资源需求

- requests: cpu 100m, memory 256Mi
- limits: cpu 500m, memory 512Mi

## 多环境

| 环境 | Intent | Namespace | Domain |
|------|--------|-----------|--------|
| skytech | k8s | techlab | hub.tech.skytech.io/works |
| office-31 | docker | — | — |
| home-134 | — | — | — |

## 运维补充

- 2026-08-04: 基于已有部署清单 `deploys/dan-flow-hub/0.1.1/` 反向提取生成
