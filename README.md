# Image Build Assistant

独立于具体研发项目的远程镜像构建助手：把业务代码留在各业务仓库里，本仓库只负责按登记信息**打包上下文 → 上传 → 在远端执行 `docker build` / `docker push`**（可选再经 `deploy.sh` 推送 K8s 清单）。

## 工作原理

```
本地                              远端构建机
┌──────────────────┐    SSH/SCP    ┌──────────────────┐
│ 1. 读取项目注册表  │ ──────────▶ │ 4. 解压构建上下文  │
│ 2. 打包构建上下文  │             │ 5. docker build   │
│ 3. 上传到远端     │             │ 6. docker push    │
└──────────────────┘             └──────────────────┘
```

**往下配置前，先分清两类输入**（避免把泛称的「配置」混为一谈）：

| 输入 | 典型文件 | 解决什么问题 |
|------|-----------|--------------|
| **远端环境文件** | `image-builder/remote.env` 或 `image-builder/remote-envs/<环境>.env`（由 `--config` 指定） | 连哪台**构建机**、SSH 与路径、**Harbor** 与是否 `push`；可选再写**部署机**（`DEPLOY_*`，仅当项目 `deploy.intent` 需要推送清单时） |
| **项目注册表** | `image-builder/projects.yaml`（由 `--projects` 指定） | 哪个业务仓库、`Dockerfile` 与构建上下文、**按环境**（`envs`）的版本与 `harbor_project`、可选 `group` / `deploy` |

脚本层不做业务判断，只消费上述文件中的字段；版本决策、是否构建、如何注册新项目由 AI 协调层完成（见 [CLAUDE.md](CLAUDE.md)）。

## 目录结构

```
image-builder/                 用户使用的工具目录
  build.sh                     统一构建入口
  deploy.sh                    部署清单推送入口（与 `projects.yaml` 中 deploy 配置配合）
  projects.yaml                项目注册表
  remote.env.example           远端配置模板
  remote.env                   默认远端配置（.gitignore，可选）
  remote-envs/                 按环境分文件（如 skytech.env，.gitignore）
  scripts/
    packaging.sh               打包构建上下文
    project-resolver.sh        项目注册表解析
    remote-exec.sh             SSH 上传与远端执行
    remote-build-entry.sh      远端执行入口脚本
    k8s-readonly-inventory.sh  单集群只读盘点（kubectl → JSON）
  logs/                        构建日志（按项目分目录，.gitignore）

agents/                        AI agent 角色定义
docs/                          项目文档
openspec/                      OpenSpec 规范工作流
tests/                         脚本级测试
CLAUDE.md                      Claude Code 协调指令
```

## 快速开始

### 1. 配置远端构建机

```bash
cp image-builder/remote.env.example image-builder/remote.env
# 编辑 remote.env，填写远端 SSH 和 Harbor 参数
```

多局域网 / 多构建机时，可复制为 `image-builder/remote-envs/<环境名>.env`（不纳入版本库），构建时用 `--config` 指向对应文件。详见 [CLAUDE.md](CLAUDE.md) 中的多环境路由说明。

### 2. 注册项目

编辑 `image-builder/projects.yaml`。**版本、Harbor 项目等按环境写在 `envs` 下**；同一逻辑产品若有多镜像（如前后端），可为每条记录设置相同的 **`group`**，用 `--group` 顺序构建整组。

```yaml
projects:
  - name: my-app
    source_dir: /path/to/my-app
    dockerfile_path: deploy/Dockerfile
    build_context: .
    image_name: my-app
    platform: linux/amd64
    enabled: true
    envs:
      - env: skytech
        version: 1.0.0
        harbor_project: ai.infra
```

可选：`group: my-product`（与组内其他镜像同名即可）。

### 3. 执行构建

默认使用 `image-builder/remote.env` 与 `image-builder/projects.yaml`：

```bash
bash image-builder/build.sh --project my-app --env skytech
```

指定环境与配置文件：

```bash
bash image-builder/build.sh \
  --config image-builder/remote-envs/skytech.env \
  --project my-app \
  --env skytech
```

**按组构建**（遍历同 `group`、且在该 `env` 下有配置、且已启用的所有项目，顺序与 YAML 一致；任一失败则停止）：

```bash
bash image-builder/build.sh \
  --config image-builder/remote-envs/skytech.env \
  --group my-product \
  --env skytech
```

## 配置说明

### 远端环境文件（`remote.env` / `remote-envs/*.env`）

字段与模板一致，见 `image-builder/remote.env.example`。下表为**构建侧常用项**（必填项以模板注释为准）。

| 字段 | 说明 | 示例 |
|------|------|------|
| `REMOTE_HOST` | 远端构建机地址 | `build.example.internal` |
| `REMOTE_PORT` | SSH 端口 | `22` |
| `REMOTE_USER` | SSH 用户名 | `builder` |
| `SSH_KEY_PATH` | SSH 私钥路径 | `~/.ssh/id_rsa` |
| `REMOTE_BASE_DIR` | 远端工作目录 | `/opt/image-build-assistant` |
| `HARBOR_HOST` | Harbor 地址；留空则镜像为 `IMAGE_NAME:VERSION` 且不 push | `harbor.example.com` |
| `HARBOR_PROJECT` | 未在 `projects.yaml` 的 env 中写 `harbor_project` 时的默认 Harbor 项目 | `library` |
| `PLATFORM` | 默认构建平台 | `linux/amd64` |
| `PUSH` | 构建后是否推送 | `true` |
| `PUSH_LATEST` | 是否同时 tag/push mutable `latest`；可由项目环境的 `push_latest` 覆盖 | `true` |

#### Deploy Host（`DEPLOY_*`，清单推送）

用于 **`deploy.sh`**：把本地 `image-builder/deploys/{project}/{version}/` 下的 YAML **SCP 到部署机**，供人在远端 `kubectl apply`。与 **构建机**（`REMOTE_*`）无关，可以是同一台机，也可以是单独运维机。

| 字段 | 运行 `deploy.sh` 时 | 说明 |
|------|---------------------|------|
| `DEPLOY_HOST` | **必填** | 部署机地址（主机名或 IP） |
| `DEPLOY_PORT` | 可选，默认 `22` | SSH 端口 |
| `DEPLOY_USER` | **必填** | SSH 用户；需能在远端创建目录并向 `DEPLOY_BASE_DIR` 下写入 |
| `DEPLOY_SSH_KEY_PATH` | **必填** | 本机 SSH 私钥路径（`ssh`/`scp` 的 `-i`） |
| `DEPLOY_BASE_DIR` | **必填** | 远端根目录；推送目标为 **`{DEPLOY_BASE_DIR}/{projects.yaml 中的项目 name}/{目录名即 version}/`**（与 `deploy.sh` 中 `basename(deploy-dir)` 一致） |

**行为摘要**（详见 `image-builder/scripts/deploy-remote-exec.sh`）：远端目标目录**已存在**时默认报错退出；加 `deploy.sh --force` 会先删远端同名目录再上传。**不在此机执行 `kubectl`**，集群操作由运维在部署机上自行进行。

仅做 **`build.sh`、从不跑 `deploy.sh`** 时，环境文件里可以不写 `DEPLOY_*`（`build.sh` 会加载但不做必填校验）。若同一文件既要构建又要推送清单，须配齐上表必填项。

更多流程见 [CLAUDE.md](CLAUDE.md)「K8s 部署流程」与 [docs/specs/k8s-deploy-intent.md](docs/specs/k8s-deploy-intent.md)。**K8s 只读盘点**在能执行 `kubectl` 的机器上运行，常与 `DEPLOY_HOST` 合一，见 [docs/k8s-readonly-inventory.md](docs/k8s-readonly-inventory.md)。

### projects.yaml

**项目层（共享）**必填：`name`、`source_dir`、`dockerfile_path`、`build_context`。

**项目层可选：**`image_name`（默认取 `source_dir` 目录名）、`platform`、`build_args`、`enabled`、`**group**`（字符串；相同 `group` 的条目可被 `--group` 一次遍历构建）。

**环境层** `envs`：至少一条 `- env: <键>`。每条下常见字段：`version`、`built_commit`、`harbor_project`；按需还有 `deploy`（如 `intent: k8s` 等）。**`name + env` 在注册表内联合唯一**。

**`group` 与 `--group`：**

- 未写 `group` 的项目不会出现在任何组构建列表中。
- 组构建只包含：**`group` 匹配**、**存在当前 `--env` 对应条目**、且 **`enabled` 为真**（或缺省）的项目。
- 组内各镜像仍各自维护 `version`；需要锁步发版时由流程或 AI 层统一 bump，脚本只负责按序调用多次构建。

版本管理字段：`version`、`built_commit` 由 AI 层在构建成功后按 [docs/specs/semver-versioning.md](docs/specs/semver-versioning.md) 等约定回写。

`source_dir` 支持绝对路径与相对路径；相对路径相对于 **`projects.yaml` 所在目录**解析。

## 命令参考

```bash
bash image-builder/build.sh [选项]
```

| 选项 | 说明 |
|------|------|
| `--project NAME` | 按注册表中的项目名构建 |
| `--group NAME` | 构建该组内所有**已启用**且在指定 `--env` 下有配置的项目（YAML 顺序；与 `--project` / `--source-dir` 互斥；**必须**同时提供 `--env`） |
| `--env NAME` | 解析注册表时使用的环境键（单项目构建可选；**组构建必填**） |
| `--source-dir PATH` | 手工指定项目源码目录（需同时指定 --dockerfile-path 和 --build-context） |
| `--dockerfile-path PATH` | Dockerfile 相对于 source-dir 的路径 |
| `--build-context PATH` | 构建上下文相对于 source-dir 的路径 |
| `--image-name NAME` | 覆盖镜像名 |
| `--harbor-project NAME` | 覆盖 Harbor 项目 |
| `--version TAG` | 指定版本标签 |
| `--platform PLATFORM` | 覆盖构建平台 |
| `--push true\|false` | 是否推送到 Harbor |
| `--push-latest true\|false` | 是否同时 tag/push mutable `latest`；version-only 发布应设为 `false` |
| `--config PATH` | 指定远端环境文件路径（默认 `image-builder/remote.env`） |
| `--projects PATH` | 指定 projects.yaml 路径 |

**说明：**`--env` 在单项目构建时可选（未指定则使用该项目的**第一个** `envs` 条目）；**使用 `--group` 时必须指定 `--env`**。

### deploy.sh（部署推送）

在镜像已构建、且 `projects.yaml` 中该项目在对应 `env` 下配置了 `deploy.intent: k8s` 时，将 **AI 已生成好的** 清单目录（通常为 `image-builder/deploys/<项目名>/<版本>/`，内含 `*.yaml`）同步到环境文件中的部署机（`DEPLOY_*`）。生成清单的步骤与字段约定见 [image-builder/deploy-conventions.md](image-builder/deploy-conventions.md)、[docs/specs/k8s-deploy-intent.md](docs/specs/k8s-deploy-intent.md)。

```bash
bash image-builder/deploy.sh \
  --config image-builder/remote-envs/skytech.env \
  --project claude-code-hub-neo \
  --env skytech \
  --deploy-dir image-builder/deploys/claude-code-hub-neo/0.6.7
```

**必填：**`--project`、`--deploy-dir`（目录下需至少一个 `.yaml`）。可选：`--force`、`--env`（解析注册表用）、`--config`、`--projects`。

## 测试

```bash
bash tests/assistant-layout.test.sh
bash tests/build-image.test.sh
bash tests/remote-exec.test.sh
bash tests/project-resolver.test.sh
bash tests/packaging.test.sh
bash tests/claude-code-hub-registration.test.sh
bash tests/docs-smoke.test.sh
bash tests/k8s-readonly-inventory.test.sh
bash tests/hedgedoc-docker-build-deps.test.sh
```

`hedgedoc-docker-build-deps`：校验 sibling 路径 `../vibe-hedgedoc/vibe-hedgedoc`（或环境变量 `HEDGEDOC_ROOT`）下前后端 Dockerfile 是否包含 Alpine 下编译 native 模块所需的 `python3` / `make` / `g++`；找不到仓库时 **SKIP**。完整 `docker build` 仍在远端或本机手动执行。

## 通过 AI 环境使用

本项目设计为在 Claude Code 等 AI 编程环境中使用。AI 作为协调者，负责分析项目、决策版本号、调用构建脚本、回写状态。你只需要用自然语言描述意图。

### 典型指令与效果

**新项目首次构建：**

```
> 新项目构建，目录在 ../../vibe-me/claude-code-hub
```

AI 会：
1. 分析目标目录结构，找到 Dockerfile
2. 注册项目到 `projects.yaml`（如果尚未注册）
3. 设定初始版本号，执行构建并推送到 Harbor
4. 回写 `version` 和 `built_commit` 到 `projects.yaml`

**日常迭代构建：**

```
> 构建 claude-code-hub
```

AI 会：

1. 读取 `projects.yaml` 中的 `version` 和 `built_commit`
2. 对比源码仓库 HEAD — 有新 commit 则自动 bump patch（如 1.0.0 → 1.0.1）并构建
3. 无新 commit 则告知"镜像已是最新"，不执行构建

**同组多镜像（如前后端）：**

```
> 用 skytech 环境构建 my-product 组
```

AI 会：

1. 在 `projects.yaml` 中找出 `group: my-product` 且在该环境下有 `envs` 条目的成员
2. 使用 `build.sh --config <对应 remote-envs/*.env> --group my-product --env skytech` 按 YAML 顺序逐个构建（必要时先为各成员做版本决策）
3. 构建成功后按成员分别回写 `version` / `built_commit`

**指定版本号：**

```
> 构建 claude-code-hub，版本 2.0.0
```

AI 会校验指定版本 > 当前版本后使用该值。如果指定的版本 <= 当前版本，会拒绝并提示。

**无变更但坚持构建：**

```
> 构建 claude-code-hub
< 镜像已是最新（commit: d74e7e1），无需构建
> 还是构建一下
```

AI 会 bump patch 后执行构建 — 每次构建都产生新版本号，不存在重复版本。

**覆盖构建（明确意图）：**

```
> 重新构建 claude-code-hub，覆盖当前版本
```

AI 识别到覆盖意图，bump patch 后构建推送。

### 版本管理规则

| 场景 | 行为 |
|------|------|
| 首次构建（`built_commit` 为空） | 使用 yaml 中的 `version` 值 |
| 有新 commit | 自动 bump patch，构建推送 |
| 无新 commit | 默认不构建，用户坚持则 bump 后构建 |
| 用户指定版本 | 校验 > 当前版本后使用 |
| 版本倒退 | 拒绝，提示当前版本 |

### 前置条件

- 在 Claude Code（或同类）会话中打开本仓库
- 已准备远端环境文件：`image-builder/remote.env` **或** `image-builder/remote-envs/<环境>.env`，并在构建/部署命令中用 `--config` 指向实际使用的文件
- 目标业务仓库中有可用的 Dockerfile（路径登记在 `projects.yaml` 的 `dockerfile_path`）

### 其它文档

- [docs/usage.md](docs/usage.md)：面向「怎么跑命令」的精简说明（与本文互补）
- [docs/k8s-readonly-inventory.md](docs/k8s-readonly-inventory.md)：单集群只读盘点脚本（`kubectl` 可用时输出 JSON）；Cursor 侧由 Skill **`k8s-cluster-snapshot`**（`.cursor/skills/k8s-cluster-snapshot/`）在澄清/部署配置时触发调用
- [CLAUDE.md](CLAUDE.md)：AI 协调、多环境路由、版本与部署回写等完整约定

## 开发协调

本仓库同时是一个多 AI agent 协同研发的模板项目：

- `agents/` — 各角色定义（spec-writer、designer、coder、reviewer 等），通过 Codex CLI / Gemini CLI 执行
- `openspec/` — 需求变更的结构化工作流
- `CLAUDE.md` — 主 agent 协调指令与串行流水线定义

详见 [CLAUDE.md](CLAUDE.md)。
