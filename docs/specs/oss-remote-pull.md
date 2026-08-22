# 开源镜像拉取构建规范（OSS Remote Pull）

> 面向场景：把开源仓库代码拉下来，构建镜像并推送。不涉及本地开发动作。
> 关联技能：`oss-image-build`（`.claude/skills/` 与 `.cursor/skills/` 双份）。

## 定位：两种源码模式

镜像构建按源码归属分为两种模式，由 `projects.yaml` 项目层字段 `source_mode` 区分（缺省为 `local`）：

| | local 模式（本地项目） | remote 模式（上游仓库拉取） |
|---|---|---|
| 适用场景 | 自己开发的项目，源码在本地 | 纯拉取上游代码构建推送，本地无开发动作 |
| 源码位置 | 本地开发目录（`source_dir` = 本地绝对路径） | builder 端 `~/code_workspaces/{repo}`，本地零源码 |
| 构建路径 | 本地打包 tar → 上传 → 远端解包 → 构建（现状） | builder 上 clone 后就地构建（新增） |
| 版本策略 | auto bump patch（见 semver-versioning.md） | 跟随上游 release tag（见下文） |
| 本地索引 | `source_dir` + `version` + `built_commit` | 额外含 `upstream_url`；`source_dir` 为 builder 端路径 |

- **local 模式是本规范的兼容基线**：现有项目、现有流程一行不改。
- **remote 模式是本规范新增的主体**：拉取、分析、构建的体力全部在 builder，本地只维护 projects.yaml 索引（上游地址、镜像名、版本、commit、部署信息）。

### 模式判定（按输入形态，无需询问）

用户首次提出构建时，按其给出的输入形态判定模式：

| 输入形态 | 模式 |
|---------|------|
| 本地目录路径（如 `/Users/gunegg/Works/...`，本地存在且可进入） | local |
| git 仓库地址（`git@...` / `https://...` / `ssh://...` 等可 clone 的 URL） | remote |
| 仅项目名（无法直接判定） | 查 projects.yaml 已注册条目的 `source_mode`；未注册则询问用户给出目录或 URL |

- local 输入 → 走现有本地构建流程（semver-versioning.md），首次构建时注册 projects.yaml 记 `source_dir` 本地路径。
- remote 输入 → 进入本规范 remote 流程，第 ① 步的 repo URL 即用户输入。
- 判定发生在 AI 层，脚本层不感知输入形态，只按 `source_mode` 执行。

## remote 模式流程

```
用户: 给出构建输入（本地目录路径 | git 仓库地址 | 已注册项目名）
  │
  ├─ ⓪ 模式判定（按输入形态，见上节）── 本地目录 → 现有 local 流程，本规范不展开
  │
  ├─ ① 输入解析（remote 模式）
  │     repo URL 即用户输入（git 可 clone 即可，不限于 GitHub）
  │     目标 env（skytech / office-31 / home-134）→ 解析 remote-envs/{env}.env
  │     env 未指定 → 询问；env 文件不存在 → 终止并列出可用 env
  │     可选 ref：tag / branch / commit，未指定默认取最新 semver tag
  │
  ├─ ② 远端拉取/更新（脚本层 remote-code-pull.sh，新）
  │     ssh builder → ~/code_workspaces/{repo} clone 或 fetch
  │     → checkout 目标 ref → 输出 JSON: 远端路径 + commit short hash + tag 列表
  │     目录冲突（同名不同上游）→ 改用 {owner}-{repo}
  │
  ├─ ③ 远端分析（AI 层）
  │     ssh builder 探测 Dockerfile（根目录 / docker/ / deploy/ / Dockerfile.* 常见命名）
  │     确定 dockerfile_path、build_context、image_name、platform
  │     无 Dockerfile → 终止并报告，不代写
  │
  ├─ ④ 注册 projects.yaml（AI 层，本地索引）
  │     source_mode: remote
  │     source_dir: ~/code_workspaces/{repo}     ← builder 端路径，远端展开 ~
  │     upstream_url: {repo URL}
  │     env 层: version / built_commit 由后续步骤回写
  │
  ├─ ⑤ 版本决策（AI 层，见下节）
  │
  ├─ ⑥ 构建（脚本层，扩展 build.sh）
  │     remote 模式: 跳过本地打包/上传，只传 entry 脚本
  │     remote-build-entry.sh 收到 REMOTE_SOURCE_DIR 后
  │     docker build -f {remote}/{dockerfile_path} {remote}/{build_context} → push Harbor
  │
  └─ ⑦ 回写（AI 层）
        构建成功 → projects.yaml 回写 version / built_commit
```

## projects.yaml 字段约定（remote 模式）

```yaml
- name: uptime-kuma
  source_mode: remote                       # 新字段，local(缺省) | remote
  source_dir: ~/code_workspaces/uptime-kuma # builder 端路径；~ 在 builder 侧展开
  upstream_url: https://github.com/louislam/uptime-kuma.git  # 新字段，remote 模式必填
  dockerfile_path: Dockerfile
  build_context: .
  image_name: uptime-kuma
  platform: linux/amd64
  enabled: true
  envs:
    - env: skytech
      version: v-1.23.13                    # 上游 tag 规范化，见下节
      built_commit: abc1234                 # checkout 的上游 commit short hash
      harbor_project: ai.infra
```

约束：

- `source_mode: remote` 的项目，`upstream_url` 必填，供后续重新拉取/更新。
- 同一项目多个 env 时，各 env 的 builder 各自维护一份 `~/code_workspaces/{repo}`（`~` 展开天然适配各 builder home）。
- `built_commit` 为上游 commit short hash，与 local 模式语义一致（版本变更检测基准）。
- `deploy.intent` 等部署字段对 remote 模式照常生效（镜像已入 Harbor，deploy.sh 流程不变）。

## 版本决策（remote 模式）

remote 模式版本**跟随上游 tag**，不使用 local 模式的 auto bump patch：

1. **取 tag**：通过 `remote-code-pull.sh tags` 或 builder 上 `git ls-remote --tags` 列出上游 tags。
2. **过滤**：只保留纯数字 semver 形 tag（`X.Y.Z` 或 `vX.Y.Z`）；`rc` / `beta` / `nightly` 等非稳定 tag 跳过；无法解析为 semver 的 tag 跳过。
3. **规范化**：去前导 `v`，加 `v-` 前缀 → `v-X.Y.Z`（如上游 `v2.1.3` → `v-2.1.3`）。
4. **选版本**：用户未指定 ref 时取最高 semver tag；用户指定 ref 时按该 ref 对应的版本规范化。
5. **无 semver tag**：终止并询问用户指定版本号（`v-X.Y.Z`）。
6. **更新检测**：上游有新 tag 时，规范化后 > 当前 `version` 方可构建（沿用「版本只能前进，不能倒退或重复」）；确认后 checkout 新 tag 并构建。
7. **构建成功后回写**：`version` + `built_commit`（该 tag 的 commit short hash）。

## 脚本层改动

| 文件 | 改动 |
|------|------|
| `scripts/remote-code-pull.sh` | 新增。子命令 `tags`（列上游全部 tag 名，JSON 输出；semver 过滤由 AI 层完成）/ `pull`（clone 或 fetch + checkout ref，输出 JSON：远端路径、commit、当前 tag）。复用 `remote-exec.sh` 的 ssh 选项约定 |
| `scripts/project-resolver.sh` | 解析 `source_mode` 与 `upstream_url` 字段（缺省 local / 空） |
| `build.sh` | `source_mode: remote` 时跳过本地 Dockerfile 存在性校验与打包，调用新的 remote-source 构建函数 |
| `scripts/remote-exec.sh` | 新增 remote-source 构建函数：只上传 entry 脚本，传入 `REMOTE_SOURCE_DIR` 等环境变量 |
| `scripts/remote-build-entry.sh` | 新增 `REMOTE_SOURCE_DIR` 分支：展开 `~`，校验远端 Dockerfile 存在，dockerfile = `{REMOTE_SOURCE_DIR}/{dockerfile_path}`，context = `{REMOTE_SOURCE_DIR}/{build_context}`，就地 docker build，跳过 unpack 流程 |

remote 模式不打包上传，`.git` 天然保留在 build context 中（`INCLUDE_GIT` 型项目可直接用 `git describe`），依赖 `.dockerignore` 排除。

## 前置条件与边界

- builder 需具备 `git` 与访问上游仓库的网络（外网）。
- 上游仓库无 Dockerfile → 终止并报告，AI 层不代写 Dockerfile。
- 同一 builder 上同一项目并发构建的竞态，v1 不处理（可接受，构建为低频操作）。
- 上游 tag 采用「注释 tag / 轻量 tag」任一；签名验证不在 v1 范围。

## 技能约定

- 技能名：`oss-image-build`；`.claude/skills/oss-image-build/SKILL.md` 与 `.cursor/skills/oss-image-build/SKILL.md` 双份，内容一致。
- 格式跟随 `k8s-cluster-snapshot`：frontmatter（name / description 含触发语）+ 中文正文 + 自然语言映射。
- 技能负责流程编排：AI 层分析与决策（输入解析、远端分析、注册索引、版本决策、回写），并调用脚本层工具执行机械步骤（`remote-code-pull.sh`、`build.sh`）。
