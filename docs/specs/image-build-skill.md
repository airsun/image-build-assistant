# image-build 技能规范（双上下文构建）

> 日期：2026-08-24
> 状态：已实施
> 对应技能：`image-build`（`.claude/skills/` 与 `.cursor/skills/` 双份，逐字节一致，测试强制）

## 背景

本地源码目录构建镜像的 AI 层规则此前只存在于本仓库的 CLAUDE.md 与 `docs/specs/semver-versioning.md`，目标项目会话加载不到；现有 `oss-image-build` 技能只覆盖 remote 流（git URL 拉取），且路径相对本仓库根。

本规范将 local 构建流封装为技能 `image-build`，支持**两种执行上下文**：

- **A. 目标项目会话（桥接模式）**：在任意业务仓库的会话中直接构建该仓库自身镜像，不打开本仓库会话。
- **B. image-build-assistant 会话（集中模式）**：维持现有集中管理行为不变。

无论哪种上下文，**状态（projects.yaml / logs/ / deploys/ / remote-envs/）一律读写本仓库** `image-builder/` 目录，目标会话绝不写本地状态。

前置探索结论：脚本层 9 个脚本全部 BASH_SOURCE 锚定、天然 cwd 无关；外部调用契约 = 入口脚本绝对路径 + 所有路径参数绝对化 + `--config` 必传。

## 技能分工

| 技能 | 输入形态 | 执行上下文 | 位置 |
|------|---------|-----------|------|
| `image-build` | 本地目录 / local 项目名 / deploy 请求 | 双上下文 | 本仓库 `.claude`/`.cursor` + 个人级 symlink |
| `oss-image-build` | git URL / remote 条目项目名 | IB 会话 | 本仓库 `.claude`/`.cursor`（未装个人级） |
| `k8s-cluster-snapshot` | 集群盘点请求（IB 的 Cursor 会话） | IB 会话 | 本仓库 `.cursor/skills/` |

触发边界：`image-build` 的 description 明确排除 git URL 输入（归 `oss-image-build`），两技能触发词刻意不重叠。`oss-image-build` 仅随本仓库加载，target 会话中不存在——target 会话遇到 URL 请求引导用户转 IB 会话。

## 安装与注册契约

`image-builder/scripts/setup-skill.sh` 负责安装（个人级，非版本控制）：

- `~/.claude/skills/image-build` → symlink 指向本仓库 `.claude/skills/image-build`（单一真相源）
- `~/.cursor/skills/image-build` → symlink 指向本仓库 `.cursor/skills/image-build`
- `~/.config/image-build-assistant/home` → 单行文本，本仓库绝对路径（`pwd -P` 结果）
- **默认不写 shell rc**：GUI 启动的 Cursor / Claude Desktop 继承 launchd 环境而非 shell rc，zshrc export 对 GUI 会话无效；config 文件对所有启动方式有效。`--with-shell-export` 可选追加 `export IMAGE_BUILD_HOME=...`（已存在同名行则替换）
- `IMAGE_BUILD_HOME` 保留为**刻意覆盖通道**（如测试另一份 checkout），setup 默认不注入

安装形态选 symlink（collab-runtime 范式）而非物理副本（weekly-report 范式）：仓库更新即全局生效，双份一致性由测试强制（`cmp -s` 断言）。

## IB_ROOT 解析链

技能文本内联执行，顺序：**env → cwd 向上探测 → config 文件 → 终止**。

签名校验（候选根同时满足）：`image-builder/build.sh` 存在 **且** `image-builder/remote.env.example` 存在（后者是 IB 独有标记，防业务仓库内嵌副本误命中）。

| 状态 | 结果 |
|------|------|
| `$IMAGE_BUILD_HOME` 命中且签名有效 | 用它（其余来源不再查） |
| env set 但签名无效 | 硬终止（不静默降级），提示重跑 setup-skill.sh |
| env 未设，cwd 向上探测命中（到 `/` 止） | 用它（IB 会话零安装可用） |
| env 未设，cwd miss，config 命中且有效 | 用它（GUI 启动会话兜底） |
| env 未设，cwd miss，config 存在但无效 | 终止，提示重跑 setup-skill.sh |
| 全部 miss | 终止，引导运行 setup-skill.sh |

顺序取舍：cwd 优先于 config——换取「IB 会话零安装可用」与「过期 config 不遮蔽有效 cwd」；config 的误命中风险由双文件签名收窄。env set 但无效 → 硬终止而非静默降级：静默回退会掩盖配置错误并可能把状态写进用户不期望的仓库。

## local 构建流（步骤 0–7）

技能内以 `${IB_ROOT}` 绝对形式呈现（不再区分完整/桥接两种指令形式）：

1. **模式判定**：本地目录 → local（本技能）；git URL → oss-image-build；仅项目名 → 查 projects.yaml 的 `source_mode`（缺省 local，`remote` 转 oss-image-build）
2. **目标环境解析**：env 未指定 → 询问；`${IB_ROOT}/image-builder/remote-envs/{env}.env` 不存在 → 终止并列可用 env
3. **注册检查**：未注册 → 探测 Dockerfile（根 / Dockerfile.* / deploy/ / docker/）定 `dockerfile_path` / `build_context` / `image_name` / `platform`；本地条目**不写 `source_mode`**，`source_dir` 写绝对路径（`cd` 取 `pwd`，不写字面 `~`）
4. **读状态**：`version` 与 `built_commit`
5. **取 HEAD**：`cd {source_dir} && git rev-parse --short HEAD`
6. **版本决策**：决策树见 `docs/specs/semver-versioning.md`（首次用当前 version 带 v- 前缀 / 变更且指定须 > 当前 / 未指定 auto bump patch / 无变更告知最新 / 覆盖意图 = bump patch）
7. **构建**：`bash ${IB_ROOT}/image-builder/build.sh --config ${IB_ROOT}/image-builder/remote-envs/{env}.env --project {name} --env {env} --version {v-X.Y.Z}`
8. **回写**：exit 0 才回写 `version` / `built_commit` 到 `${IB_ROOT}/image-builder/projects.yaml`

## deploy 指引（intent: k8s）

构建回写成功后检查 `deploy.intent`：`k8s` → 走指引；`docker` / 缺失 → 不触发。指引级步骤（细节以 `docs/specs/k8s-deploy-intent.md` 为准）：

1. 读 `image-builder/deploy-conventions.md`（全局规约）
2. 读 `image-builder/projects/{name}.md`（deploy note，存在时）
3. 可选盘点：`bash ${IB_ROOT}/image-builder/scripts/k8s-readonly-inventory.sh`（kubectl 可用时；IB 的 Cursor 会话中此触发由 k8s-cluster-snapshot 技能覆盖）
4. YAML 生成到 `image-builder/deploys/{name}/{version}/`
5. `bash ${IB_ROOT}/image-builder/deploy.sh --config ... --project {name} --env {env} --deploy-dir ${IB_ROOT}/image-builder/deploys/{name}/{version}`
6. 推送成功回写 `deployed_version` / `deployed_commit`

范围声明：技能只给指引，不做 YAML 生成细节、不做 k8s 盘点全量纳入。

## 前置条件与边界

- `--config` 必须显式传绝对路径（默认 `${SCRIPT_DIR}/remote.env` 不存在，漏传必失败）
- 本地 `source_dir` 必须绝对路径（project-resolver.sh 不展开 `~`；remote 条目 `~/code_workspaces/...` 是远端语义，勿动）
- env 文件内 `SSH_KEY_PATH` / `DEPLOY_SSH_KEY_PATH` 写绝对路径（字面 `~` 不会被本地 ssh 展开）
- `${IB_ROOT}/image-builder/logs/` 需可写（构建日志写工具链目录）
- 并发构建 / 双会话同时写 projects.yaml 的竞态 v1 不处理
- 技能执行是单会话顺序流程，不涉及 subagent 流水线
- 已知风险（本次不改脚本，记录在案）：`remote-exec.sh:16` 的 `SSH_KEY_PATH` 字面 tilde 在部分 ssh 版本下按 cwd 相对解析失败

## 关联测试

- `tests/assistant-layout.test.sh`：布局存在性 + 双份一致 + 结构标记断言
- `tests/setup-skill.test.sh`：安装脚本行为（HOME 覆盖、夹具、幂等、保护语义）
- 测试计划：`docs/test-plans/image-build-skill.md`；评审：`docs/reviews/image-build-skill-2026-08-24.md`
