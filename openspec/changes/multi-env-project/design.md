## Context

multi-env-config 假设"项目不跨环境构建"，但实际场景需要同一项目在多个局域网构建。当前 resolver 的 awk 脚本按 `name` 找到第一个匹配就返回，无法区分同名的不同 env 记录。

## Goals / Non-Goals

**Goals:**

- 同名项目按 `name + env` 联合键区分
- 每条记录独立维护 version、built_commit、harbor_project、deploy 等状态
- 共享 source_dir、dockerfile_path、build_context、image_name（值相同但各自声明）
- `--env` 不传时保持原有 name-only 匹配行为

**Non-Goals:**

- 不做项目定义和状态的分层存储（思路 B）
- 不做跨环境版本同步

## Decisions

### D1: resolver awk 匹配增加 env 过滤

`project_resolver_parse_field` 和 `project_resolver_parse_deploy_field` 接受可选的 `env_name` 参数。awk 匹配逻辑：
1. 遇到 `- name: X` → 进入候选模式
2. 候选模式中遇到 `env: Y` → 如果 env_name 非空且不匹配，退出候选；如果匹配或 env_name 为空，确认为目标项目
3. 候选模式中遇到下一个 `- name:` → 如果 env_name 为空（不过滤），使用第一个匹配（兼容）；否则继续搜索

简化实现：由于 env 字段总是紧跟 name 之后，可以在 `in_project` 判定后立即检查 env 行。

### D2: build.sh / deploy.sh 新增 `--env` 参数

`--env` 值传给 resolver 的 env_name 参数。AI 层同时传 `--config`（env 文件路径）和 `--env`（resolver 匹配键）。

### D3: `resolve_project_by_name` 签名扩展

新签名：`resolve_project_by_name registry_path project_name [env_name]`

第三参数可选，不传或为空时退化为原有行为。

## Risks / Trade-offs

**[Trade-off] 同名项目的共享字段（source_dir 等）需要重复声明** → 可接受：项目数少，重复几行不是问题。未来如果项目多了可以考虑分层。

**[Risk] --env 忘记传导致匹配错误记录** → AI 层在 CLAUDE.md 中明确：构建时始终传 --env。单 env 项目不传也无害（name 唯一）。
