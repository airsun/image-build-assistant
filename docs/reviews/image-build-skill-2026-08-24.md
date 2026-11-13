# 评审记录：image-build 技能（双上下文构建）

- **日期**：2026-08-24
- **评审对象**：`docs/specs/image-build-skill.md` 对应的双份 SKILL.md + `image-builder/scripts/setup-skill.sh` + `tests/assistant-layout.test.sh`（扩展）+ `tests/setup-skill.test.sh`（新增）
- **评审方式**：独立 agent 对抗式评审（换源，非实现者本人）；setup 脚本用假 HOME 夹具实测全部 11 个用例；SKILL.md 触发边界与 IB_ROOT 解析链做失效模式推演；与老规划（`docs/plans/2026-05-30-封版为全局独立技能.md`）逐项核对偏差
- **结论**：**APPROVE**（无 CRITICAL / MAJOR；3 个 MINOR 全部处置）

## 处置表

| # | 发现 | 严重度 | 处置 |
|---|------|--------|------|
| 1 | 测试用例共享 FAKE_HOME：stale-symlink 用例的 `ln -s` 在已存在 symlink 上 EEXIST，用例间状态泄漏 | MINOR | ✅ 修复：每用例独立 HOME（`new_home()` 计数器），状态零泄漏 |
| 2 | macOS TMPDIR（`/var/folders/...`）是符号链接，测试侧 `$WORK` 与脚本侧 `pwd -P` 结果（`/private/var/...`）字符串不等，symlink 目标断言误报 | MINOR | ✅ 修复：测试侧 `WORK` 先 `pwd -P` 规范化后再拼接断言路径 |
| 3 | `expect_failure` 调用处残留 `|| true`，会把 fail 退出码吞掉导致假 PASS | MINOR | ✅ 修复：删除 `|| true`，失败路径由 `expect_failure` 内部 fail 处理 |

## 验证为「非 bug」的关键检查项

- **IB_ROOT 解析链顺序**（env → cwd → config）：env set 但签名无效 → 硬终止（不静默降级）符合「显式用户意图最高优先级」；cwd 优先于 config 换取 IB 会话零安装可用——与老规划「完整/桥接双模式」的偏差已在老规划文档记录
- **签名校验**：`build.sh` + `remote.env.example` 双文件，后者是 IB 独有标记；业务仓库内嵌 image-builder 副本误命中风险收窄，本机无此类副本
- **symlink 保护语义**：指向别处 → 拒绝并要求 `--force`；普通目录 → 拒绝且**绝不删除**（哨兵文件实测完好）
- **默认不写 zshrc**：GUI 启动的 Cursor / Claude Desktop 继承 launchd 环境，config 文件覆盖所有启动方式——与用户环境事实（settings.json 已迁移走 env）一致
- **脚本层契约**：全部路径参数绝对化 + `--config` 必传，与既有 9 个脚本的 BASH_SOURCE 锚定审计结论一致；`build.sh` 参数名（--config/--project/--env/--version）逐字核对 build.sh:100-148
- **触发边界**：image-build description 排除 git URL，与 oss-image-build 触发词零重叠（grep 核对）

## 未能验证（需真机/真会话）

- 目标会话中技能的实际加载（依赖重启 Claude Code / Cursor 后的技能发现机制）
- 真实构建链路（步骤 7 的远端 docker build）：组件级已由既有测试覆盖，端到端留待可选冒烟
- GUI 启动会话下 config 文件路径的实际命中（机制已推演，未在 GUI 会话实测）

## 评审后测试状态

- `tests/setup-skill.test.sh`：11 用例全通过
- `tests/assistant-layout.test.sh`：扩展断言（4 条 required_paths + cmp + 4 个结构标记 + 反向断言）在 spec 落地后全绿
- 全量回归：见测试执行阶段记录（`docs/test-plans/image-build-skill.md` 通过标准）
