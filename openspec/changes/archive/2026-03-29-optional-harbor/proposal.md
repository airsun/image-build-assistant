## Why

部分环境的构建服务器同时也是运行服务器，不存在 Harbor 仓库，镜像构建后本机 `docker run` / `docker-compose` 直接使用。当前 `build.sh` 和 `remote-build-entry.sh` 强制要求 HARBOR_HOST，且镜像 tag 始终拼接 Harbor 路径前缀，无法适配这类场景。

## What Changes

- `build.sh` 中 HARBOR_HOST 校验从必填改为可选
- `remote-build-entry.sh` 镜像 tag 拼接增加条件分支：有 HARBOR_HOST 用 `harbor/project/name:version`，无 HARBOR_HOST 用 `IMAGE_NAME:version`
- 无 HARBOR_HOST 时 `PUSH` 自动视为 `false`，跳过推送
- 更新 `remote.env.example` 标注 HARBOR_HOST 为可选

## Capabilities

### New Capabilities

### Modified Capabilities
- `build-logging`: 构建日志中的镜像名需反映实际 tag（有/无 Harbor 前缀），不影响日志结构

## Impact

- **脚本层**：`build.sh`（放松校验）、`remote-build-entry.sh`（tag 拼接分支）
- **配置**：无 Harbor 的 env 文件不填 HARBOR_HOST/HARBOR_PROJECT，`PUSH=false`
- **现有行为**：有 HARBOR_HOST 的环境完全不受影响
