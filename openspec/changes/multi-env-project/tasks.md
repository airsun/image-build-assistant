## 1. project-resolver 改造 [backend] [medium]

- [x] 1.1 `project_resolver_parse_field` — 新增可选 `env_name` 参数，awk 匹配 name 后增加 env 过滤
- [x] 1.2 `project_resolver_parse_deploy_field` — 同上
- [x] 1.3 `resolve_project_by_name` — 签名扩展为 `(registry_path, project_name, env_name?)`，存在性检查和字段解析均传入 env_name

## 2. build.sh / deploy.sh 新增 --env [backend] [simple]

- [x] 2.1 `build.sh` — parse_args 新增 `--env`，reset_state 新增 `REQUESTED_ENV`，resolve_project 传入 env
- [x] 2.2 `deploy.sh` — 同上

## 3. 文档更新 [backend] [simple]

- [x] 3.1 CLAUDE.md — 更新构建调用示例，增加 `--env` 参数说明
