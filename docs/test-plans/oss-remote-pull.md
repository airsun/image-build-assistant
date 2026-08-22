# 测试策略：OSS Remote Pull（remote 源码模式）

> 对应规范：`docs/specs/oss-remote-pull.md`
> 测试文件：`tests/oss-remote-pull.test.sh`（新增）、`tests/assistant-layout.test.sh`（扩展）
> 环境：纯本地 bash，无网络依赖（ssh/git/docker 全部用 shell 函数遮蔽或夹具目录模拟）

## 测试层次与范围

| 层 | 覆盖 | 手段 |
|----|------|------|
| 解析层 | project-resolver 新字段（source_mode/upstream_url）、remote 路径不本地化 | 临时 YAML 夹具 + resolve_project_by_name |
| 校验层 | build.sh remote 分支校验（upstream_url 必填、PUSH_LATEST 规则对 remote 同样生效） | 直接 source build.sh 调 validate_inputs |
| 远端入口层 | remote-build-entry.sh 的 ~ 展开、目录/Dockerfile 校验、context 解析 | source 脚本 + 临时目录夹具 |
| 拉取脚本层 | remote-code-pull.sh 的 JSON 转义、tag 解析去重、pull 输出解析、失败路径 | 遮蔽 `ssh` 函数注入假远端输出 |
| 布局层 | 新文件进入 required_paths（脚本 + spec + 双份 skill） | 扩展 assistant-layout.test.sh |

## 关键用例（按风险排序）

### 1. resolver：remote 路径保持 verbatim（高风险）
- 夹具：`source_dir: ~/code_workspaces/foo` + `source_mode: remote` → `SOURCE_DIR` 仍为 `~/code_workspaces/foo`（不拼接 registry 目录）
- 夹具：`source_mode` 缺省 → 解析为 `local`，路径按既有规则本地化
- 夹具：`upstream_url` 存在 → 解析正确；缺省 → 空串

### 2. build.sh remote 校验
- `SOURCE_MODE=remote` + `UPSTREAM_URL` 空 → validate_inputs 失败
- `SOURCE_MODE=remote` + `UPSTREAM_URL` 非空 → 通过，且不触碰本地路径（不要求 SOURCE_DIR 本地存在）
- `PUSH_LATEST` 非法值在 remote 模式同样被拒

### 3. remote-build-entry：remote 模式
- `REMOTE_SOURCE_DIR=~/code_workspaces/x` → init 后展开为 `${HOME}/code_workspaces/x`
- `remote_entry_resolve_context_dir`：`BUILD_CONTEXT=.` → REMOTE_SOURCE_DIR；`subdir` → `REMOTE_SOURCE_DIR/subdir`
- `remote_entry_stage_remote_source`：目录不存在 → 失败；Dockerfile 不存在 → 失败；正常夹具 → 通过
- 回归：无 REMOTE_SOURCE_DIR 时仍走 upload 模式（UPLOADED_* 必填校验不变）

### 4. remote-code-pull（遮蔽 ssh）
- `remote_code_pull_json_string`：反斜杠、双引号转义
- `remote_code_pull_default_name`：URL 去 .git 取 basename
- `cmd_tags`：annotated tag 的 `^{}` 重复行去重、输出为 JSON 数组
- `cmd_pull`：解析 `path|commit|ref` 输出为 JSON；ssh 失败（exit 1）→ 函数失败不产出 JSON
- 参数校验：`--config` 缺失 → 失败；config 文件不存在 → 失败

### 5. 布局
- required_paths 追加：`image-builder/scripts/remote-code-pull.sh`、`docs/specs/oss-remote-pull.md`、双份 skill 文件

## 不覆盖（明示边界）
- 真实 ssh / git clone / docker build：需要内网 builder，由真机验证（首次实际拉取构建时执行）
- remote 模式端到端（build.sh 完整 main）：main 内 ssh 无法低成本遮蔽，拆分为函数级验证（覆盖路径均已测）
- 并发构建竞态：v1 明确不处理

## 通过标准
- `tests/oss-remote-pull.test.sh` 全部断言通过
- 存量回归测试（除已确认的 2 个漂移失败外）保持通过
- shellcheck：新代码零 warning（info 级 SC2317/SC1091 仓库惯用豁免）
