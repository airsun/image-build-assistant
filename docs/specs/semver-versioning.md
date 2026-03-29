# 镜像版本管理规范

AI 层在调用 `build.sh` 前后执行版本决策，脚本层只接收 `--version` 参数。

## 版本号格式

所有镜像版本号采用 **`v-` 前缀 + semver**  格式：`v-X.Y.Z`

示例：`v-0.1.0`、`v-1.2.3`

### 前缀规则

- `projects.yaml` 中的 `version` 字段存储完整版本号（含前缀），如 `v-0.1.0`
- `--version` 参数传递完整版本号
- Docker tag 使用完整版本号：`image:v-0.1.0`
- `BUILD_ARGS` 中的 `${VERSION}` 展开为完整版本号

### 历史版本兼容

已有项目如果 `version` 字段不含 `v-` 前缀（如 `1.0.2`），在下次构建时自动迁移到新格式：
1. 按正常逻辑决定版本号（bump 或用户指定）
2. 给结果加上 `v-` 前缀
3. 回写到 `projects.yaml`

## 构建前：版本决策

### 步骤 1：读取当前状态

从 `projects.yaml` 读取目标项目的：
- `version` — 当前镜像版本（`v-X.Y.Z` 格式）
- `built_commit` — 上次构建对应的 commit short hash（可能为 null）

### 步骤 2：获取源码 HEAD

```bash
cd $source_dir && git rev-parse --short HEAD
```

### 步骤 3：决策分支

```
built_commit 为空（首次构建）
  → 使用当前 version 值构建（确保带 v- 前缀）

HEAD != built_commit（有变更）
  → 用户指定了版本？
    → 指定值 > 当前 version？→ 使用指定值（确保带 v- 前缀）
    → 指定值 <= 当前 version？→ 拒绝："版本不能倒退，当前为 v-X.Y.Z"
  → 未指定版本？
    → auto bump patch（v-X.Y.Z → v-X.Y.(Z+1)）

HEAD == built_commit（无变更）
  → 告知用户："镜像已是最新（commit: xxx），无需构建"
  → 用户坚持构建？
    → 是 → auto bump patch 并构建
    → 否 → 终止
```

### 步骤 4：调用构建

```bash
bash build.sh --project <name> --version <决定的版本号>
```

## 构建后：回写状态

构建成功后（`build.sh` 返回 0），更新 `projects.yaml`：
- `version` → 本次使用的版本号（含 `v-` 前缀）
- `built_commit` → 步骤 2 获取的 HEAD commit hash

## Semver bump 规则

- 版本比较和 bump 操作基于去掉 `v-` 前缀后的数字部分
- 仅自动 bump patch 位
- major / minor 级别的 bump 需要用户显式指定
- 版本只能前进，不能倒退或重复
