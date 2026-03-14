## Why

当前助手代码嵌套在同名子目录 `image-build-assistant/image-build-assistant/` 中，项目根目录充斥着空占位目录（`src/`）和旧兼容壳（`deploy/`），结构混乱。同时，助手的职责边界不清晰——脚本层和 AI 层的分工没有明确约定。需要扁平化目录结构，明确"Claude Code 负责智能分析，脚本只管执行"的分层模型，并将构建日志集中管理。

## What Changes

- **BREAKING** 删除嵌套的 `image-build-assistant/` 子目录，将 `bin/`、`lib/`、`config/`、`remote/` 提升到项目根目录
- **BREAKING** 删除 `deploy/` 兼容壳目录（`remote-build.sh`、`remote-build-entry.sh`、`remote-build.env.example`）
- 删除空的 `src/` 目录
- 删除 `tests/remote-build-compat.test.sh` 兼容性测试
- 新增 `logs/{project-name}/` 目录，脚本执行时自动 tee 日志到此处
- 合并内层 `image-build-assistant/tests/` 到根 `tests/`
- 合并内层 `image-build-assistant/docs/` 到根 `docs/`
- 更新 `CLAUDE.md` 中的目录约定，明确 AI 层/脚本层职责分工

## Capabilities

### New Capabilities
- `build-logging`: 构建日志集中存储到助手目录 `logs/{project-name}/{timestamp}.log`，脚本执行时通过 tee 自动留痕

### Modified Capabilities

（无现有 spec，不涉及修改）

## Impact

- `bin/build-image.sh`：所有路径引用需从 `image-build-assistant/` 子目录调整为项目根
- `lib/*.sh`：source 路径调整
- `tests/*.sh`：路径引用调整，删除兼容性测试
- `config/projects.yaml`：`source_dir` 的相对路径基准变化（从 `config/` 到根的距离变了）
- `CLAUDE.md`：目录约定部分需重写，增加 AI 层/脚本层职责说明
