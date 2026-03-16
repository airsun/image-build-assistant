## Why

`remote.env` 的职责是定义"构建推送到哪"（远端连接 + Harbor 全局配置），但当前混入了 `IMAGE_NAME` 和 `VERSION` 两个 per-project / per-build 的字段。`IMAGE_NAME=placeholder` 还会通过 `source` 污染 shell 环境，导致 `merge_project_settings()` 的 fallback 链命中 `placeholder` 而非预期的目录名推断值。

## What Changes

- 从 `remote.env` 和 `remote.env.example` 中删除 `IMAGE_NAME` 和 `VERSION` 行
- 在 `build_image_load_remote_config()` 中显式 unset `IMAGE_NAME` 和 `VERSION`，防止残留环境变量干扰 merge 逻辑

## Capabilities

### New Capabilities

_无新增能力_

### Modified Capabilities

_无 spec 级别的行为变更。本次是配置卫生清理，不改变构建行为语义。_

## Impact

- `image-builder/remote.env` — 删除两行
- `image-builder/remote.env.example` — 删除两行
- `image-builder/build.sh` — `build_image_load_remote_config()` 增加 unset 保护
- 依赖 `IMAGE_NAME` 全局默认值的使用场景（目前不存在）会受影响，但这本身就是 bug
