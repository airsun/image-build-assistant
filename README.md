# Image Build Assistant

独立于具体研发项目的远程镜像构建助手。将"项目研发"和"镜像构建 / 推送"彻底拆开——本仓库不承载业务代码，只负责打包、上传、在远端执行 `docker build` 和 `docker push`。

## 工作原理

```
本地                              远端构建机
┌──────────────────┐    SSH/SCP    ┌──────────────────┐
│ 1. 读取项目注册表  │ ──────────▶ │ 4. 解压构建上下文  │
│ 2. 打包构建上下文  │             │ 5. docker build   │
│ 3. 上传到远端     │             │ 6. docker push    │
└──────────────────┘             └──────────────────┘
```

## 目录结构

```
image-builder/                 用户使用的工具目录
  build.sh                     统一构建入口
  projects.yaml                项目注册表
  remote.env.example           远端配置模板
  remote.env                   远端配置（.gitignore）
  scripts/
    packaging.sh               打包构建上下文
    project-resolver.sh        项目注册表解析
    remote-exec.sh             SSH 上传与远端执行
    remote-build-entry.sh      远端执行入口脚本
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

### 2. 注册项目

编辑 `image-builder/projects.yaml`，添加项目：

```yaml
projects:
  - name: my-app
    source_dir: /path/to/my-app
    dockerfile_path: deploy/Dockerfile
    build_context: .
    image_name: my-app
    harbor_project: library
    platform: linux/amd64
    enabled: true
```

### 3. 执行构建

```bash
bash image-builder/build.sh --project my-app
```

## 配置说明

### remote.env

| 字段 | 说明 | 示例 |
|------|------|------|
| `REMOTE_HOST` | 远端构建机地址 | `build.example.internal` |
| `REMOTE_PORT` | SSH 端口 | `22` |
| `REMOTE_USER` | SSH 用户名 | `builder` |
| `SSH_KEY_PATH` | SSH 私钥路径 | `~/.ssh/id_rsa` |
| `REMOTE_BASE_DIR` | 远端工作目录 | `/opt/image-build-assistant` |
| `HARBOR_HOST` | Harbor 仓库地址 | `harbor.example.com` |
| `HARBOR_PROJECT` | 默认 Harbor 项目 | `library` |
| `PLATFORM` | 默认构建平台 | `linux/amd64` |
| `PUSH` | 构建后是否推送 | `true` |

### projects.yaml

每个项目必填字段：`name`、`source_dir`、`dockerfile_path`、`build_context`。

可选字段：`image_name`（默认取目录名）、`harbor_project`、`platform`、`enabled`。

`source_dir` 支持相对路径，相对于 `projects.yaml` 所在目录解析。

## 命令参考

```bash
bash image-builder/build.sh [选项]
```

| 选项 | 说明 |
|------|------|
| `--project NAME` | 按注册表中的项目名构建 |
| `--source-dir PATH` | 手工指定项目源码目录（需同时指定 --dockerfile-path 和 --build-context） |
| `--dockerfile-path PATH` | Dockerfile 相对于 source-dir 的路径 |
| `--build-context PATH` | 构建上下文相对于 source-dir 的路径 |
| `--image-name NAME` | 覆盖镜像名 |
| `--harbor-project NAME` | 覆盖 Harbor 项目 |
| `--version TAG` | 指定版本标签（默认时间戳） |
| `--platform PLATFORM` | 覆盖构建平台 |
| `--push true\|false` | 是否推送到 Harbor |
| `--config PATH` | 指定 remote.env 路径 |
| `--projects PATH` | 指定 projects.yaml 路径 |

## 测试

```bash
bash tests/assistant-layout.test.sh
bash tests/build-image.test.sh
bash tests/remote-exec.test.sh
bash tests/project-resolver.test.sh
bash tests/packaging.test.sh
bash tests/claude-code-hub-registration.test.sh
bash tests/docs-smoke.test.sh
```

## 开发协调

本仓库同时是一个多 AI agent 协同研发的模板项目：

- `agents/` — 各角色定义（spec-writer、designer、coder、reviewer 等），通过 Codex CLI / Gemini CLI 执行
- `openspec/` — 需求变更的结构化工作流
- `CLAUDE.md` — 主 agent 协调指令与串行流水线定义

详见 [CLAUDE.md](CLAUDE.md)。
