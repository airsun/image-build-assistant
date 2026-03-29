## 1. 配置目录结构 [backend] [simple]

- [x] 1.1 创建 `image-builder/remote-envs/` 目录
- [x] 1.2 将当前 `remote.env` 内容复制为 `remote-envs/skytech.env`，保留 `remote.env` 作为 fallback
- [x] 1.3 更新 `remote.env.example`，标注其作为模板适用于每份环境 env 文件

## 2. project-resolver 扩展 [backend] [simple]

- [x] 2.1 `project_resolver_clear` 新增 `ENV_NAME=""` 重置
- [x] 2.2 `resolve_project_by_name` 新增 `ENV_NAME` 字段解析（复用 `project_resolver_parse_field`）

## 3. projects.yaml 更新 [backend] [simple]

- [x] 3.1 为现有项目添加 `env: skytech` 字段

## 4. CLAUDE.md 多环境说明 [backend] [simple]

- [x] 4.1 在 CLAUDE.md 中补充多环境路由的 AI 层行为说明（env 字段 → env 文件路径 → --config 参数）

## 5. docs/specs 同步 [backend] [simple]

- [x] 5.1 在 `docs/specs/` 下创建或更新环境路由相关规范文档，整合 env-routing spec 内容
