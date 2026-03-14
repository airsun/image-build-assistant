# 镜像构建助手

这是一个**独立于具体研发项目**的远程镜像构建助手目录，用于把“项目研发 / 二开”和“镜像构建 / 推送”彻底拆开。

它本身不承载业务代码，只负责：

- 读取远端构建配置
- 读取项目注册表
- 打包项目构建上下文
- 上传到远端 Linux 构建机
- 在远端执行 `docker build` / `docker push`

## 目录说明

- `bin/build-image.sh`：统一入口命令
- `config/remote.env`：远端 SSH / Harbor 默认配置
- `config/projects.yaml`：项目注册表
- `lib/`：项目解析、打包、远端执行公共逻辑
- `remote/remote-build-entry.sh`：上传到远端后执行的入口
- `logs/`：构建日志（按项目名分目录）
- `tests/`：脚本级 smoke tests

## 配置说明

### 1. 远端配置 `remote.env`

先复制模板：

```bash
cp config/remote.env.example config/remote.env
```

典型字段包括：

- `REMOTE_HOST`
- `REMOTE_PORT`
- `REMOTE_USER`
- `SSH_KEY_PATH`
- `REMOTE_BASE_DIR`
- `HARBOR_HOST`
- `HARBOR_PROJECT`
- `PLATFORM`
- `PUSH`

这些字段描述的是**远端构建机**和默认镜像参数，不绑定某个具体项目。

### 2. 项目注册表 `projects.yaml`

每个项目最少登记：

- `name`
- `source_dir`
- `dockerfile_path`
- `build_context`

可选：

- `image_name`
- `harbor_project`
- `platform`
- `enabled`

项目注册表支持相对路径，`source_dir` 会相对 `projects.yaml` 所在目录解析。

## 使用方式

按项目名执行：

```bash
bash bin/build-image.sh --project claude-code-hub
```

如果需要临时覆盖参数，可以追加：

```bash
bash bin/build-image.sh \
  --project claude-code-hub \
  --version v1.2.3 \
  --platform linux/amd64
```

也可以不用注册表，直接手工指定路径：

```bash
bash bin/build-image.sh \
  --source-dir /path/to/project \
  --dockerfile-path deploy/Dockerfile \
  --build-context .
```

## Harbor 说明

`Harbor` 登录仍然在**远端构建机**完成，不在本地 `remote.env` 中放账号密码。

建议先在远端构建机上用构建账号执行：

```bash
docker login harbor.tech.skytech.io
```

后续助手会复用远端当前账号的 Docker 登录态。

## 远端约束

远端仅需提供必要环境：

- `bash`
- `tar`
- `docker`
- 可 SSH 登录

远端每次构建前会清理本次运行对应的代码工作区，但不会主动清理 Docker layer cache。
