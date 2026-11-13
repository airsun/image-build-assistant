---
name: image-build
description: >-
  Use when the user asks to build/push a docker image from a LOCAL source
  directory or a registered project name (构建镜像 / 打镜像 / 构建当前项目 /
  把 {项目} 构建推到 {env} / bump 版本 / 部署清单 / 推 k8s 清单), or to deploy a
  built image per k8s intent. Works in any working directory: either the
  image-build-assistant repo session (centralized mode) or any target project
  session (bridged mode), locating the assistant repo via IMAGE_BUILD_HOME /
  config file / upward probe. NOT for git URLs (https://, git@, ssh://) — those
  belong to the oss-image-build skill.
---

# 镜像构建（image-build）

本地源码目录 → AI 层决策 → 远端构建 → 推送 Harbor → 状态回写。双上下文可用：目标项目会话或 image-build-assistant 会话。
完整规范：`${IB_ROOT}/docs/specs/image-build-skill.md`；本地流版本决策细节以 `${IB_ROOT}/docs/specs/semver-versioning.md` 为准。

## 0. 定位与状态集中声明

- 本技能承载 **local 流**（本地源码目录构建）全流程 + **deploy 指引**（k8s intent）。
- **无论在哪执行，状态一律读写 `${IB_ROOT}/image-builder/`**：projects.yaml、logs/、deploys/、remote-envs/。目标项目会话绝不写本地状态。
- 技能执行是单会话顺序流程，**不涉及 subagent 流水线**（流水线是 image-build-assistant 模板自身的迭代机制，不在本技能范围）。

## 1. 步骤 0：模式判定与 IB_ROOT 解析

**模式判定（不询问用户）：**

| 输入形态 | 模式 | 归属 | 执行上下文 |
|---------|------|------|-----------|
| 本地目录路径（存在） | local | 本技能 | 双上下文均可 |
| 仅项目名 | 查 projects.yaml 的 `source_mode` | 缺省 local → 本技能；`remote` → oss-image-build | 本技能双上下文；remote 条目转 IB 会话 |
| git 仓库地址（https:// / git@ / ssh://） | remote | **oss-image-build** | IB 会话（target 会话不加载该技能，引导转 IB 会话） |

**IB_ROOT 解析链**（按序探测，命中即用；全部基于 bash 内建与 cd/pwd）：

1. **env**：`${IMAGE_BUILD_HOME:-}` 非空 → 校验签名；**set 但签名无效 → 硬终止**（不静默降级，提示重跑 setup-skill.sh）。
2. **cwd 向上探测**：从 `$(pwd)` 起逐级 `dirname` 向上，到 `/` 止。
3. **config 文件**：`~/.config/image-build-assistant/home` 内容（单行绝对路径）→ 校验签名。

签名校验：候选根同时存在 `image-builder/build.sh` **且** `image-builder/remote.env.example`（后者是 IB 独有标记，防业务仓库内嵌副本误命中）。

```bash
# signature check — both files must exist
[[ -f "${candidate}/image-builder/build.sh" && -f "${candidate}/image-builder/remote.env.example" ]]
```

**失效模式表：**

| 状态 | 结果 |
|------|------|
| env 命中且签名有效 | 用它（其余来源不再查） |
| env set 但签名无效 | 终止：提示 `IMAGE_BUILD_HOME` 指向无效路径，重跑 `bash ${IB_ROOT}/image-builder/scripts/setup-skill.sh` |
| env 未设，cwd 链命中 | 用它 |
| env 未设，cwd miss，config 命中且有效 | 用它 |
| env 未设，cwd miss，config 存在但无效 | 终止：提示重跑 setup-skill.sh |
| 全部 miss | 终止：引导运行 `bash <IB>/image-builder/scripts/setup-skill.sh` 或手工设置 `IMAGE_BUILD_HOME` |

## 2. local 构建流（步骤 1–7）

1. **目标环境解析**：env 未指定 → 询问。`${IB_ROOT}/image-builder/remote-envs/{env}.env` 不存在 → 终止并列出可用 env（`ls ${IB_ROOT}/image-builder/remote-envs/*.env`）。
2. **注册检查**：读 `${IB_ROOT}/image-builder/projects.yaml`。项目未注册 → 探测源码目录 Dockerfile（根 / Dockerfile.* / deploy/ / docker/），确定 `dockerfile_path` / `build_context` / `image_name` / `platform`，注册本地条目：**不写 `source_mode`**（缺省 local），`source_dir` 写绝对路径（`cd` 目标目录取 `pwd` 结果，不写字面 `~`）。
3. **读状态**：该 env 条目的 `version` 与 `built_commit`（可能为 null）。
4. **取 HEAD**：`cd {source_dir} && git rev-parse --short HEAD`。
5. **版本决策**（决策树以 `${IB_ROOT}/docs/specs/semver-versioning.md` 为准）：
   - `built_commit` 空（首次构建）→ 用当前 `version`（确保 `v-` 前缀）
   - HEAD ≠ built_commit，用户指定版本 → 指定值须 > 当前，否则拒绝（"版本不能倒退，当前为 v-X.Y.Z"）
   - HEAD ≠ built_commit，未指定 → auto bump patch
   - HEAD == built_commit → 告知"镜像已是最新（commit: xxx）"；用户坚持 → bump patch 后构建
   - "覆盖/重新构建"意图 → 不覆盖同版本，bump patch 后构建
6. **构建**：

   ```bash
   bash ${IB_ROOT}/image-builder/build.sh \
     --config ${IB_ROOT}/image-builder/remote-envs/{env}.env \
     --project {name} --env {env} --version {v-X.Y.Z}
   ```

7. **回写**：exit 0 才回写 `version` → 本次版本、`built_commit` → HEAD hash 到 `${IB_ROOT}/image-builder/projects.yaml` 对应 env 条目。

## 3. deploy 指引节（intent: k8s）

构建回写成功后，检查该 env 条目 `deploy.intent`：`k8s` → 走本流程；`docker` / 缺失 → 不触发 YAML 流。生成细节一律以 `${IB_ROOT}/docs/specs/k8s-deploy-intent.md` 为准，本技能只给指引：

1. 读 `${IB_ROOT}/image-builder/deploy-conventions.md`（全局规约）
2. 读 `${IB_ROOT}/image-builder/projects/{name}.md`（deploy note，存在时；覆盖规约默认值）
3. 可选盘点：`bash ${IB_ROOT}/image-builder/scripts/k8s-readonly-inventory.sh`（kubectl 可用时；**IB 会话的 Cursor 中此触发由 k8s-cluster-snapshot 技能覆盖**，避免双重定义）
4. YAML 生成到 `${IB_ROOT}/image-builder/deploys/{name}/{version}/`（按 00–06 编号清单）
5. 推送：

   ```bash
   bash ${IB_ROOT}/image-builder/deploy.sh \
     --config ${IB_ROOT}/image-builder/remote-envs/{env}.env \
     --project {name} --env {env} \
     --deploy-dir ${IB_ROOT}/image-builder/deploys/{name}/{version}
   ```

6. 推送成功后回写 `deployed_version` / `deployed_commit`。

范围声明：本技能只给指引，不做 YAML 生成细节、不做 k8s 盘点全量纳入。

## 4. 与 oss-image-build 的路由边界

| 输入 | 归属技能 | 说明 |
|------|---------|------|
| git URL | oss-image-build | remote 流（拉取上游 → 就地构建）；仅随 IB 仓库加载，target 会话中不存在 → target 会话遇到 URL 请求引导用户转 IB 会话 |
| 本地目录 / local 项目名 | 本技能 | 双上下文 |
| remote 条目项目名 | oss-image-build | projects.yaml `source_mode: remote` 的条目走 remote 流，在 IB 会话执行 |

触发词刻意不重叠：本技能 description 排除 git URL 输入。

## 5. 前置条件与边界

- **`--config` 必须显式传绝对路径**（默认 `${SCRIPT_DIR}/remote.env` 不存在，漏传必失败）。
- **`source_dir` 必须绝对路径**（project-resolver.sh 不做 `~` 展开；remote 条目 `~/code_workspaces/...` 是远端语义，勿动）。
- env 文件内 `SSH_KEY_PATH` / `DEPLOY_SSH_KEY_PATH` 写绝对路径（字面 `~` 不会被本地 ssh 展开）。
- `${IB_ROOT}/image-builder/logs/` 目录需可写（构建日志写工具链目录）。
- 并发构建竞态 v1 不处理；双会话同时写 projects.yaml 不处理。
- 上游更新 / 新环境首次使用：先确保 env 文件存在（remote-envs/ 不入版本控制，需按 remote.env.example 手工配置）。
- 首次跨项目使用：运行 `bash <IB>/image-builder/scripts/setup-skill.sh` 完成安装（symlink + 定位注册）。

## 6. 自然语言映射（触发）

用户说类似以下内容，按本技能处理：**构建当前项目**、**把 {项目} 打镜像推到 {env}**、**{项目} 有新提交，构建一下**、**给 {项目} bump 版本并构建**、**部署 {项目} 到 k8s**、**把 {项目} 的 k8s 清单推上去**、**build image for {source_dir} to {env}**。
