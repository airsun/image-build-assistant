---
name: oss-image-build
description: >-
  Use when the user gives a git repository URL (https://, git@, ssh://) and asks
  to pull it and build/push an image, or says 拉取开源代码构建镜像 / 上游仓库构建 /
  第三方项目镜像 / clone 后构建, or asks to build an upstream OSS project image in
  the image-build-assistant repo. Not for local source dirs — those follow the
  existing local build flow.
---

# OSS 镜像拉取构建（oss-image-build）

上游仓库代码 → builder 远端拉取 → 就地构建 → 推送 Harbor。本地零源码，projects.yaml 仅作索引。
完整规范：`../../../docs/specs/oss-remote-pull.md`（本技能只承载路由与决策规则，细节以 spec 为准）。

## 何时使用

**按输入形态判定模式，不询问用户：**

| 输入形态 | 模式 | 走法 |
|---------|------|------|
| 本地目录路径 | local | 现有本地构建流程（semver-versioning.md），本技能不适用 |
| git 仓库地址（https:// / git@ / ssh://） | remote | 本技能 |
| 仅项目名 | 查 projects.yaml | 已注册 → 按 `source_mode`；未注册 → 询问用户给出目录或 URL |

## 核心流程（remote 模式）

1. **输入解析**：repo URL + 目标 env。`image-builder/remote-envs/{env}.env` 不存在 → 终止并列出可用 env；env 未指定 → 询问。
2. **列 tag（版本决策输入）**：

   ```bash
   bash image-builder/scripts/remote-code-pull.sh tags \
     --config image-builder/remote-envs/{env}.env --repo-url {URL}
   ```

   过滤：只取 `X.Y.Z` / `vX.Y.Z` 纯数字 tag，跳过 rc/beta/nightly；取最高者。
3. **拉取/更新（脚本层）**：

   ```bash
   bash image-builder/scripts/remote-code-pull.sh pull \
     --config image-builder/remote-envs/{env}.env --repo-url {URL} --ref {tag}
   ```

   输出 JSON 索引（`remote_path` / `commit` / `ref`），注册与回写以它为准。
4. **远端分析（AI 层）**：ssh 探测 builder 上仓库的 Dockerfile 位置，确定 `dockerfile_path` / `build_context` / `image_name`。
   **凭据一律取 env 文件**（`SSH_KEY_PATH` / `REMOTE_USER` / `REMOTE_HOST` / `REMOTE_PORT`），不硬编码 key 路径。
   无 Dockerfile → 终止并报告，不代写。
5. **注册 projects.yaml**（本地索引）：

   ```yaml
   - name: {name}
     source_mode: remote
     source_dir: ~/code_workspaces/{name}   # 取 pull 输出的 remote_path
     upstream_url: {URL}
     dockerfile_path: {探测结果}
     build_context: .
     image_name: {name}
     platform: linux/amd64
     enabled: true
     envs:
       - env: {env}
         version: {v-X.Y.Z}
         built_commit: {pull 输出的 commit}
         harbor_project: {决策规则见下}
   ```

6. **版本决策**：跟随上游 tag → 规范化 `v-X.Y.Z`（去前导 `v`，加 `v-` 前缀）。沿用「版本只能前进」；不做本地 patch 递增。
7. **构建**：

   ```bash
   bash image-builder/build.sh --config image-builder/remote-envs/{env}.env \
     --project {name} --env {env} --version {v-X.Y.Z}
   ```

8. **回写**：构建成功后把 `version` / `built_commit` 写入 projects.yaml 对应 env 条目。

## 决策规则

| 决策点 | 规则 |
|--------|------|
| 镜像版本 | 上游稳定 tag 规范化；无 semver tag → 询问用户指定 `v-X.Y.Z` |
| harbor_project | 跟随**同环境既有项目**的取值；无既有项目则用 env 文件默认 |
| push_latest | 询问用户；服务类镜像建议 `false` |
| 目录冲突 | builder 上同名目录属于不同上游 → 改用 `{owner}-{repo}` 作 name（`--name`） |
| deploy 段 | 用户未要求部署则不注册；要求部署时走 K8s 部署流程 |

## 前置条件与边界

- builder 需 `git` + 可访问上游仓库的外网；不通 → 报告并停下。
- 上游更新：重跑 `tags` + `pull`，新 tag 规范化后 > 当前 version 才可构建。
- 同一 builder 上同一项目并发构建竞态，v1 不处理。

## 自然语言映射（触发）

用户说类似以下内容，按本技能处理：**把这个仓库拉下来构建镜像**、**构建 {URL} 的镜像推送到 {env}**、**拉取开源项目打成镜像**、**上游有新版本，更新镜像**、**把 {项目} 的镜像升级到 vX.Y.Z**。
