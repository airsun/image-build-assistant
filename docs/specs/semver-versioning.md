# 镜像版本管理规范

AI 层在调用 `build.sh` 前后执行版本决策，脚本层只接收 `--version` 参数。

## 构建前：版本决策

### 步骤 1：读取当前状态

从 `projects.yaml` 读取目标项目的：
- `version` — 当前镜像版本（semver 格式）
- `built_commit` — 上次构建对应的 commit short hash（可能为 null）

### 步骤 2：获取源码 HEAD

```bash
cd $source_dir && git rev-parse --short HEAD
```

### 步骤 3：决策分支

```
built_commit 为空（首次构建）
  → 使用当前 version 值构建

HEAD != built_commit（有变更）
  → 用户指定了版本？
    → 指定值 > 当前 version？→ 使用指定值
    → 指定值 <= 当前 version？→ 拒绝："版本不能倒退，当前为 X.Y.Z"
  → 未指定版本？
    → auto bump patch（X.Y.Z → X.Y.(Z+1)）

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
- `version` → 本次使用的版本号
- `built_commit` → 步骤 2 获取的 HEAD commit hash

## Semver bump 规则

- 仅自动 bump patch 位
- major / minor 级别的 bump 需要用户显式指定
- 版本只能前进，不能倒退或重复
