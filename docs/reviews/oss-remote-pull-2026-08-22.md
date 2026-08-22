# 评审记录：OSS Remote Pull（remote 源码模式）

- **日期**：2026-08-22
- **评审对象**：`docs/specs/oss-remote-pull.md` 对应的脚本层 5 处改动
- **评审方式**：独立 agent 对抗式评审（换源，非实现者本人），对生成的远程命令做了实际执行验证（本地 git 仓库模拟 fresh clone / re-pull / origin 冲突 / annotated tags / branch-tag 同名 / POSIX sh 兼容 / 恶意 %q 值）
- **结论**：**APPROVE**（无 CRITICAL / MAJOR；8 个 MINOR 全部处置）

## 处置表

| # | 发现 | 严重度 | 处置 |
|---|------|--------|------|
| 1 | 无 `--ref` 的 `pull` 对已存在 checkout 只 fetch 不切换，HEAD 停在旧 tag，JSON 报告旧 commit 为当前 | MINOR | ✅ 修复：无 ref 时 checkout 到 `origin/HEAD` 指向的默认分支 |
| 2 | branch 与 tag 同名时，`git checkout` DWIM 优先本地分支，遮蔽同名 tag | MINOR | ✅ 修复：checkout 顺序改为 `refs/tags/` → `origin/` → 裸 ref |
| 3 | `--config` 等参数缺值时 `$2` unbound variable 崩溃，无 usage 提示 | MINOR | ✅ 修复：`[[ $# -ge 2 && -n "$2" ]]` 守卫 |
| 4 | repo URL 前无 `--` 分隔，`-` 开头 URL 被当 git 选项 | MINOR | ✅ 修复：`git ls-remote --tags --` / `git clone --` |
| 5 | `IFS='\|'` 解析：git ref 名允许含 `\|`，会错位污染 JSON 索引 | MINOR | ✅ 修复：分隔符改 tab（git ref 名禁止 tab） |
| 6 | spec 脚本层表写「列上游 semver tags」，与「脚本层不做智能判断」原则不符 | MINOR | ✅ spec 措辞改为「列全部 tag 名，semver 过滤由 AI 层完成」 |
| 7 | fetch 错误被 `2>/dev/null` 吞掉，checkout 失败一律报「ref not found」，误导排障 | MINOR | ✅ 修复：删除冗余二次 fetch；失败时探测 ref 是否存在，区分「checkout failed（脏树/fetch 失败）」与「ref not found」 |
| 8 | `"~"*` 匹配会误展开 `~user/` 路径 | MINOR | ✅ 修复：匹配收紧为 `"~/"*` |

## 验证为「非 bug」的检查项

- `%q` 注入：恶意 name/URL/ref（`'`、`$(...)`、空格、`;`）在生成的远程命令中按字面量传递，无逃逸（实测）
- 波浪号语义：`WS=~/code_workspaces` 在 bash 与 POSIX sh 下均正确展开；`env REMOTE_SOURCE_DIR=~/...` 在 sh 下不展开但 entry 脚本的 `${HOME}` 防御性再展开兜底，端到端正确（实测）
- annotated tag 去重、空 tag 列表 `[]`、commit-hash ref、origin 冲突报错退出、ssh 失败无 JSON 输出（实测）
- local 流程回归：`remote_exec_upload_and_execute` 未动，entry 脚本 local 分支行为逐字节一致，`normalize_dockerfile_path` 引号修复等价

## 未能验证（需真机）

- builder 实际登录 shell 类型（bash vs dash）——代码对两者都兼容，未实测
- sshd motd/banner 对 stdout 契约的影响（command 会话通常不打 motd，但取决于主机配置）
- 真机端到端 `build.sh` remote 路径（scp/ssh + docker on builder，组件级已验证）
- builder 上 git 版本对 checkout DWIM 行为的影响（影响 #2 的触发条件）

## 评审后测试状态

- `tests/oss-remote-pull.test.sh`：全断言通过（含 4 个针对修复行为的新断言）
- 存量回归 8 项全部 PASS（agentic / claude-code-hub 两个漂移失败为存量问题，与本改动无关，见测试执行阶段记录）
- shellcheck：新代码零 warning/error
