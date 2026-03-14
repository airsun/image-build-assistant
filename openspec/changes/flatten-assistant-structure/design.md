## Context

当前项目结构存在嵌套问题：助手代码在 `image-build-assistant/image-build-assistant/` 内，外层有空占位目录和旧兼容壳。经过探索讨论，确定了三项核心决策：

1. 项目根目录就是助手的工作目录，消除嵌套
2. Claude Code 负责项目分析和智能判断，脚本层只做纯执行
3. 构建日志集中存储在助手目录，不污染项目源码目录

现有代码已实现完整的远程构建闭环（打包 → SSH 上传 → 远端 docker build/push），逻辑本身不需要重写，只需调整路径引用和新增日志能力。

## Goals / Non-Goals

**Goals:**
- 扁平化目录：`bin/`、`lib/`、`config/`、`remote/` 直接在项目根下
- 清除废弃代码：`deploy/` 兼容壳、空 `src/`、兼容性测试
- 新增 `logs/` 集中日志，脚本执行时自动 tee
- 更新 `CLAUDE.md` 明确 AI 层/脚本层职责

**Non-Goals:**
- 不重写构建逻辑本身（打包、SSH、远端执行）
- 不引入新的配置格式（保持 projects.yaml + remote.env）
- 不实现项目自动发现/扫描（分析由 Claude Code AI 层完成，不在脚本中）

## Decisions

### 1. 内容提升而非重命名

将 `image-build-assistant/` 子目录的内容直接提升到项目根，而不是重命名子目录。

原因：项目根已有 `CLAUDE.md`、`agents/`、`docs/` 等文件，不能简单地用子目录替换根目录。需要逐项合并。

### 2. 脚本内 tee 实现日志

在 `build-image.sh` 的 `build_image_main` 函数中，执行前创建日志目录并通过 tee 同时输出到终端和日志文件。

替代方案：调用方重定向（`| tee logs/...`）。不采用，因为手动调用 `build-image.sh` 时不会有日志，不符合"执行器负责留痕"的定位。

### 3. projects.yaml 中 source_dir 使用绝对路径

扁平化后，`config/` 从 `image-build-assistant/config/` 变为根下 `config/`，相对路径基准发生变化。为避免混乱，建议在迁移时将 `source_dir` 统一为绝对路径，或者保持相对路径但基于 projects.yaml 文件所在目录解析（现有 `project_resolver_normalize_source_dir` 已支持）。

决策：保持现有解析逻辑不变（相对路径基于 YAML 文件所在目录），迁移时只需调整相对路径的层级。

### 4. 合并测试和文档

- `image-build-assistant/tests/*.test.sh` → `tests/`
- `image-build-assistant/docs/usage.md` → `docs/usage.md`
- `image-build-assistant/docs/claude-code-hub-example.md` → `docs/claude-code-hub-example.md`

## Risks / Trade-offs

- [路径引用遗漏] 所有 shell 脚本中的 `ASSISTANT_ROOT` 等路径计算需要逐一检查调整 → 通过测试覆盖验证
- [日志目录膨胀] `logs/` 长期累积可能变大 → `.gitignore` 排除 `logs/`，不纳入版本控制
- [projects.yaml 相对路径失效] 扁平化后基准目录变化 → 迁移时更新路径值
