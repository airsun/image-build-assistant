## Context

`remote.env` 通过 `source` 加载，其中 `IMAGE_NAME=placeholder` 和 `VERSION=v0.0.1` 会留在 shell 环境中。`merge_project_settings()` 的 fallback 链 `${IMAGE_NAME:-${DEFAULT_IMAGE_NAME}}` 会误命中 `placeholder`。

## Goals / Non-Goals

**Goals:**
- 从 `remote.env` 移除不属于远端环境配置的字段（`IMAGE_NAME`、`VERSION`）
- 防止 source 后的环境污染影响 merge 逻辑

**Non-Goals:**
- 不修改 `projects.yaml` 的结构
- 不修改 `merge_project_settings()` 的逻辑（移除污染源后其 fallback 自然正确）

## Decisions

1. **在 `build_image_load_remote_config()` 中 `source` 后显式 `unset IMAGE_NAME VERSION`**
   - 替代方案：用 `env -i` 隔离 source → 过度工程，会丢失其他需要的变量
   - 替代方案：只删 env 文件中的行不做 unset → 用户可能手动加回或环境变量残留，不够健壮

## Risks / Trade-offs

- [用户已有自定义 `remote.env` 含 `IMAGE_NAME`] → unset 保护确保即使文件中有也不会污染
- [极低风险] 如有脚本依赖 `remote.env` 中的 `IMAGE_NAME` 全局值 → 当前无此用法，且本身是 bug
