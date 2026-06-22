# 镜像构建助手

这是一个**独立于具体研发项目**的远程镜像构建助手目录，用于把「项目研发 / 二开」和「镜像构建 / 推送」彻底拆开。

它本身不承载业务代码，只负责：

- 读取**远端环境文件**（`remote.env` 或 `remote-envs/*.env`）：**远端** SSH、构建目录、**Harbor**、是否推送；可选部署机参数
- 读取**项目注册表** `projects.yaml`：源码路径、Dockerfile、**按环境**（`envs`）的版本与 `harbor_project` 等
- 打包构建上下文、上传到远端 Linux 构建机、在远端执行 `docker build` / `docker push`

更完整的概念落点与部署说明见仓库根目录 [README.md](../README.md) 与 [CLAUDE.md](../CLAUDE.md)。

## 目录说明

- `image-builder/build.sh`：统一构建入口
- `image-builder/deploy.sh`：将已生成的 K8s 清单目录推送到部署机（需 `deploy.intent: k8s` 等前置条件，见 README）
- `image-builder/remote.env.example`：环境文件模板；可复制为 `remote.env` 或 `remote-envs/<环境名>.env`
- `image-builder/projects.yaml`：项目注册表（**`harbor_project` / `version` 写在各 `envs` 条目下**）
- `image-builder/scripts/`：项目解析、打包、远端执行公共逻辑
- `image-builder/logs/`：构建日志（按项目名分目录）
- `tests/`：脚本级 smoke tests

## 配置说明

### 1. 远端环境文件

```bash
cp image-builder/remote.env.example image-builder/remote.env
# 多环境时：复制为 remote-envs/skytech.env 等，构建时用 --config 指向该文件
```

典型字段包括：`REMOTE_HOST`、`REMOTE_PORT`、`REMOTE_USER`、`SSH_KEY_PATH`、`REMOTE_BASE_DIR`、`HARBOR_HOST`、`HARBOR_PROJECT`、`PLATFORM`、`PUSH`。不填 `HARBOR_HOST` 时可只做本地 tag、不 push。

### 2. 项目注册表 `projects.yaml`

每个项目至少包含：`name`、`source_dir`、`dockerfile_path`、`build_context`，以及 **`envs`**（至少一条 `- env: <键>`，其下写 `version`、`harbor_project` 等）。

可选：`image_name`、`platform`、`enabled`、`build_args`、**`group`**（与 `build.sh --group` 配合，一次按序构建同组多镜像）。

`source_dir` 相对路径相对于 `projects.yaml` 所在目录解析。

## 使用方式

按项目名与**环境键**（与 `envs` 中 `env:` 一致）：

```bash
bash image-builder/build.sh --project claude-code-hub --env skytech
```

指定环境文件（与 `projects.yaml` 中的环境命名对应）：

```bash
bash image-builder/build.sh \
  --config image-builder/remote-envs/skytech.env \
  --project claude-code-hub \
  --env skytech
```

临时覆盖参数示例：

```bash
bash image-builder/build.sh \
  --project claude-code-hub \
  --env skytech \
  --version v1.2.3 \
  --platform linux/amd64
```

同组多镜像（`group` 相同的多条注册）：

```bash
bash image-builder/build.sh \
  --config image-builder/remote-envs/skytech.env \
  --group my-product \
  --env skytech
```

不用注册表、直接指定路径：

```bash
bash image-builder/build.sh \
  --source-dir /path/to/project \
  --dockerfile-path deploy/Dockerfile \
  --build-context .
```

## Harbor 说明

**Harbor** 登录在**远端构建机**上完成，不在本地环境文件里写仓库密码。建议先在远端用构建账号执行 `docker login <your-harbor-host>`，后续构建复用远端 Docker 登录态。

## 远端约束

远端仅需：`bash`、`tar`、`docker`、可 SSH 登录。每次构建前会清理本次运行的工作区，不主动清 Docker layer cache。
