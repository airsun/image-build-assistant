# 独立镜像构建助手设计

> 日期: 2026-03-07
> 状态: 已确认

## 背景

当前远程镜像构建能力以脚本形式放在 `claude-code-hub` 外层目录中，虽然已经实现了本地触发、远端构建、推送 Harbor 的闭环，但它本质上仍然是围绕单个项目演进出来的。

新的目标是将“项目研发 / 二开”与“远程镜像构建 / 仓库推送”彻底分层，形成一个**独立于任意本地研发项目目录**的镜像构建助手。该助手需要能够服务多个本地项目，并通过统一约定完成远端构建与推送。

## 目标

- 让镜像构建助手成为一个独立目录，而不是嵌在某个研发项目中
- 支持多个本地项目复用同一套远端构建逻辑
- 保持项目接入门槛最低，仅要求提供源码目录、Dockerfile 路径、构建上下文
- 保持现有远端构建方式：本地上传，远端构建，Harbor 登录留在远端
- 以当前 `claude-code-hub` 作为第一批迁移样本

## 方案选择

采用**独立助手目录 + 中央项目注册表 + 手工路径覆盖**方案。

原因如下：

1. **比纯调度器更稳定**
   单纯手工传路径虽然灵活，但容易误填构建参数。中央注册表可以让常用项目有固定配置，减少出错。

2. **比项目内配置优先更独立**
   如果所有配置都写在项目仓库里，镜像构建能力仍然会继续附着在业务项目上，不符合彻底分层的目标。

3. **比小型构建平台更轻**
   现阶段优先级是简单，不引入 UI、数据库、任务队列、自动扫描等复杂能力。

## 总体架构

整体分成两层：

### 1. 独立构建助手目录

该目录独立存在，负责：

- 保存远端 SSH / Harbor 默认配置
- 保存多个项目的构建注册信息
- 提供统一构建入口
- 承担打包、上传、远端执行、日志输出等公共逻辑

### 2. 研发项目目录

每个研发项目只负责自身源代码和镜像构建物料，例如：

- `Dockerfile`
- `docker-compose.yaml`
- 部署文件
- 项目私有脚本

镜像构建助手不要求项目内必须提供统一命名的构建脚本，只要求项目能暴露最小构建信息。

## 目录结构设计

建议独立助手目录采用如下结构：

```text
image-build-assistant/
├─ bin/
│  └─ build-image.sh
├─ config/
│  ├─ remote.env
│  └─ projects.yaml
├─ lib/
│  ├─ packaging.sh
│  ├─ remote-exec.sh
│  └─ project-resolver.sh
├─ remote/
│  └─ remote-build-entry.sh
├─ docs/
│  └─ usage.md
├─ logs/
└─ tests/
```

说明如下：

- `bin/`：统一命令入口
- `config/remote.env`：远端默认配置，例如 SSH、Harbor 默认项目、平台等
- `config/projects.yaml`：中央项目注册表
- `lib/`：公共函数库，拆分打包、项目参数解析、远端执行逻辑
- `remote/`：上传到远端执行的标准入口脚本
- `docs/`：使用说明
- `logs/`：本地执行日志，可选
- `tests/`：脚本级测试

## 项目注册表设计

每个项目最小登记以下字段：

- `name`
- `source_dir`
- `dockerfile_path`
- `build_context`

可选字段：

- `image_name`
- `harbor_project`
- `platform`
- `enabled`

### 示例

```yaml
projects:
  - name: claude-code-hub
    source_dir: /Users/me/work/claude-code-hub/claude-code-hub
    dockerfile_path: deploy/Dockerfile
    build_context: .
    image_name: claude-code-hub
    harbor_project: library
    platform: linux/amd64
    enabled: true
```

设计原则：

- 最小约定，不强迫项目改造目录结构
- 项目构建参数尽量集中到助手目录维护
- 保留手工覆盖能力，避免注册表僵化

## 构建上下文约定

`build_context` 表示实际传给 Docker 的构建目录。

典型形态：

- `.`：项目根目录作为上下文，最常见
- `services/api`：子目录作为上下文，适合单仓多服务
- `dist`：仅分发产物目录作为上下文

该字段很关键，因为：

- `Dockerfile` 中的 `COPY` / `ADD` 只能访问上下文内文件
- 本地打包上传到远端的，本质上也是这份上下文目录
- 上下文太大影响传输效率，上下文太小会导致构建失败

## 执行流程

统一执行入口建议为：

```bash
bin/build-image.sh --project claude-code-hub
```

内部流程如下：

1. 读取 `config/remote.env`
2. 读取 `config/projects.yaml`
3. 根据项目名找到目标项目
4. 合并最终参数
5. 校验 `source_dir`、`dockerfile_path`、`build_context`
6. 打包构建上下文
7. 上传到远端
8. 远端清理代码工作区
9. 远端执行标准化 `docker build` / `docker push`
10. 输出构建日志和镜像结果

## 参数优先级

建议固定为：

`命令行参数 > 项目注册表 > 远端默认配置`

这样可以兼顾：

- 日常按项目名执行，操作简单
- 特殊情况下临时覆盖 tag、platform、镜像项目
- 默认配置集中管理，不在每个项目里重复书写

## 远端执行策略

沿用当前已确认的约束：

- 本地只负责触发和上传
- 远端负责实际 `docker build` 与 `docker push`
- 远端构建前必须清理代码工作区和临时文件
- 不主动清理 Docker layer cache
- Harbor 登录留在远端，通过远端 Docker 登录态复用

远端构建机只需要提供必要环境：

- `bash`
- `tar`
- `docker`
- SSH 可达

## `claude-code-hub` 迁移策略

`claude-code-hub` 作为第一批迁移样本，迁移方式建议如下：

1. 将当前外层远程构建脚本中的公共逻辑迁入独立助手目录
2. 在助手的 `projects.yaml` 中新增 `claude-code-hub` 注册项
3. 构建 `claude-code-hub` 时不再依赖其外层目录中的专用调度脚本
4. 当前项目中的旧调度脚本后续可删除，或保留一个兼容提示壳

这样可以避免未来第二个、第三个项目继续把通用构建能力复制回业务仓库。

## 错误处理

为保证简单与稳定，错误处理保持分阶段中止：

- SSH 不可达：本地立即失败
- 注册表无此项目：本地立即失败
- 路径校验失败：本地立即失败
- 上传失败：不进入远端解包阶段
- 解包失败：删除本次不完整工作目录
- 构建失败：保留日志，清理本次源码目录
- 推送失败：保留日志并返回失败退出码

## 非目标

本次设计明确不包含以下内容：

- Web UI
- 任务队列
- 自动扫描全盘项目
- 构建历史数据库
- 强制所有项目引入统一脚本
- 将 Harbor 凭据回收至本地配置

## 验收标准

第一阶段验收以以下结果为准：

- 独立助手目录可以脱离任意研发项目存在
- `claude-code-hub` 能作为注册项目被成功构建
- 新增第二个项目时，只需新增注册信息，不需要复制脚本
- 远端代码工作区在构建前会清理
- Docker layer cache 保持正常复用
- 日志能清晰显示项目、版本和执行参数

## 结论

这次重构的本质不是“继续给 `claude-code-hub` 增加脚本”，而是将现有单项目远程构建能力抽象成一个可复用的独立助手，并以 `claude-code-hub` 作为首个迁移样本完成验证。
