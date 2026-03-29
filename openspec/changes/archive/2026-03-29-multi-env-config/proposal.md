## Why

助手在不同局域网工作，每个网络有独立的构建服务器、Harbor 仓库和部署目标。当前 `remote.env` 单文件模型只能指向一套基础设施，切换网络时需要手动编辑 env 文件内容，容易出错且无法追溯。需要一种按环境隔离配置、按项目声明归属的方式，让构建和部署自动路由到正确的基础设施。

## What Changes

- 新增 `image-builder/remote-envs/` 目录，每个局域网环境一份 `.env` 文件，包含该网络的全套连接配置（build host + Harbor + deploy host）
- `projects.yaml` 项目条目新增 `env` 字段，声明该项目归属的环境名（对应 `remote-envs/{env}.env`）
- AI 层构建/部署流程增加环境路由：读取项目 `env` 字段 → 解析到 env 文件路径 → 通过 `--config` 传给 `build.sh` / `deploy.sh`
- 保留 `remote.env` 作为 fallback：未声明 `env` 的项目回退到原有行为，向后兼容
- 脚本层（`build.sh`、`deploy.sh`、`remote-exec.sh`、`deploy-remote-exec.sh`）零改动，已有的 `--config` 参数足够支撑

## Capabilities

### New Capabilities
- `env-routing`: 多环境配置组织与路由——按环境分文件存储连接配置，项目通过 `env` 字段声明归属，AI 层据此自动选择正确的配置文件

### Modified Capabilities
- `semver-versioning`: 构建前版本决策流程中，AI 层需在调用 `build.sh` 时额外解析 `env` 字段并传入对应的 `--config` 路径

## Impact

- **配置文件**：`remote.env` 从"唯一配置"降级为"默认 fallback"，实际配置迁移到 `remote-envs/` 目录
- **projects.yaml**：新增 `env` 字段，`project-resolver.sh` 需解析该字段
- **AI 层**：构建和部署的调用链增加一步环境路由（在 `--config` 参数赋值前）
- **CLAUDE.md**：需补充多环境路由的 AI 层行为说明
- **现有项目**：无 `env` 字段时回退 `remote.env`，零迁移成本
