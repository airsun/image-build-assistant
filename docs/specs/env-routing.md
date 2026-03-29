# 多环境路由规范

助手在多个局域网环境工作，每个环境有独立的构建服务器、Harbor 仓库（可选）和部署目标（可选）。环境配置按文件隔离，项目通过嵌套的 `envs` 段声明归属，AI 层自动路由到正确的基础设施。

## 环境配置目录结构

`image-builder/remote-envs/` 目录存放按环境命名的 `.env` 文件，每个文件包含一个局域网环境的全套远端连接配置。文件名格式为 `{env-name}.env`，`env-name` 使用 kebab-case。

每份文件包含：
- Build host（必填）：REMOTE_HOST、REMOTE_PORT、REMOTE_USER、SSH_KEY_PATH、REMOTE_BASE_DIR
- Harbor（可选）：HARBOR_HOST、HARBOR_PROJECT — 不填时不 push，镜像 tag 为纯 IMAGE_NAME:VERSION
- Deploy host（可选）：DEPLOY_HOST、DEPLOY_PORT、DEPLOY_USER、DEPLOY_SSH_KEY_PATH、DEPLOY_BASE_DIR

文件格式与 `remote.env.example` 一致，脚本层可直接 `source`。

## projects.yaml 结构

项目字段分两层：共享字段在项目层，per-env 字段嵌套在 `envs` 内。以 `name + env` 为联合唯一键。

```yaml
- name: claude-code-hub-neo
  source_dir: /path/to/source
  dockerfile_path: deploy/Dockerfile
  build_context: .
  image_name: claude-code-hub-neo
  platform: linux/amd64
  build_args: APP_VERSION=${VERSION}
  enabled: true
  envs:
    - env: skytech
      version: 0.6.7
      built_commit: 616d4b8e
      harbor_project: ai.infra
      deploy:
        intent: k8s
        namespace: claude-hub
        cluster: default
        domain: hub.ai.internal
        container_port: 3000
    - env: home-134
      version: 0.1.0
```

| 层级 | 字段 |
|------|------|
| 项目层 | name, source_dir, dockerfile_path, build_context, image_name, platform, build_args, enabled |
| env 层 | env, version, built_commit, harbor_project |
| deploy 层（env 内） | intent, namespace, cluster, domain, container_port, deployed_version, deployed_commit |

## project-resolver 解析

`resolve_project_by_name(registry_path, project_name, env_name?)` 按两层结构解析：

- 项目层字段通过 `project_resolver_parse_field` 解析
- env 层字段通过 `project_resolver_parse_env_field` 解析
- deploy 层字段通过 `project_resolver_parse_env_deploy_field` 解析

`env_name` 不传时自动取第一个 env 条目（向后兼容）。

## AI 层路由规则

AI 层在调用 `build.sh` 或 `deploy.sh` 前执行环境路由：

```
确定目标项目和环境 → image-builder/remote-envs/{env}.env → --config + --env 传给脚本
env 文件不存在 → 终止操作，列出可用 env 文件
```

### 构建调用示例

```bash
bash build.sh --config image-builder/remote-envs/skytech.env --project hub-neo --env skytech --version v-0.6.8
```

### 部署调用示例

```bash
bash deploy.sh --config image-builder/remote-envs/skytech.env --project hub-neo --env skytech --deploy-dir image-builder/deploys/hub-neo/v-0.6.8
```

## 约束

- 每个项目必须有 `envs` 段，至少包含一个 env 条目
- 同名项目可存在于多个环境，各自维护独立的版本状态和部署配置
- 构建与部署使用同一份 env 文件（同环境内聚）
- env 文件包含凭据信息，由 `.gitignore` 排除版本控制
