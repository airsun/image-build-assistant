## Why

同一个项目需要在不同局域网环境中构建（如 skytech 和 home-134）。当前 `projects.yaml` 用 `name` 做唯一键，一个项目只能绑定一个环境。需要支持同名项目以 `name + env` 为联合键存在多条记录，各自维护独立的版本状态和部署配置。

## What Changes

- `projects.yaml` 允许同名项目出现多条记录，以 `name + env` 为联合唯一键
- `project-resolver.sh` 查找逻辑从按 `name` 匹配改为按 `name + env` 匹配
- `build.sh` 和 `deploy.sh` 新增 `--env` 参数，传给 resolver 做精确匹配
- AI 层构建时将项目的 `env` 值同时传给 `--env` 和 `--config`

## Capabilities

### New Capabilities

### Modified Capabilities
- `env-routing`: resolver 查找从 name 唯一匹配改为 name + env 联合匹配，build.sh / deploy.sh 新增 --env 参数

## Impact

- **脚本层**：`project-resolver.sh`（awk 匹配逻辑）、`build.sh`（新增 --env）、`deploy.sh`（新增 --env）
- **projects.yaml**：同名项目可出现多次
- **AI 层**：构建调用增加 `--env` 参数
- **向后兼容**：`--env` 不传时按原有 name-only 匹配，单 env 项目不受影响
