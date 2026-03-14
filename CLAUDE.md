# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目定位

多 subagent 协同研发的 Claude Code 项目目录模板。通过模块化 agent 定义实现角色分工，主 agent 担任协调者，按串行流水线调度各 subagent 完成从 spec 到交付的全流程。

## 角色注册

每个 agent 的完整定义在 `agents/` 目录下，独立维护，可替换。

| Agent | 文件 | 工具 | 用途 |
|-------|------|------|------|
| spec-writer | `agents/spec-writer.md` | Claude Opus | 将需求转化为 OpenSpec 规范 |
| designer | `agents/designer.md` | Gemini CLI | 交互设计 |
| coder | `agents/coder.md` | Codex CLI | 编码实现 |
| reviewer | `agents/reviewer.md` | Codex CLI | 代码评审 |
| test-strategist | `agents/test-strategist.md` | Claude | 测试策略设计 |
| test-executor | `agents/test-executor.md` | Codex CLI | 测试编写与执行 |

执行某个 agent 前，先读取对应的 `agents/*.md` 了解其职责、输入输出和质量标准。

## 串行流水线

**核心约束：主 agent 不直接编写业务代码。** 所有代码实现、评审、测试编写必须通过对应的 subagent（Codex / Gemini CLI）完成。主 agent 的角色是协调者：调度 subagent、传递上下文、检查产出、决定流转。

### OpenSpec 集成

当通过 `/opsx:apply` 进入实施阶段时，**不按 OpenSpec 默认的逐任务直接实现**，而是将 OpenSpec 的任务列表映射到本项目的串行流水线：

1. **Spec 整合** — 将 `openspec/changes/{name}/specs/` 下的 spec 文件整合为 `docs/specs/{feature}.md`
2. **进入流水线** — 按 `designer → coder → reviewer → test-strategist → test-executor` 顺序执行
3. **任务勾选** — 流水线各阶段完成后，回到 OpenSpec 的 `tasks.md` 批量勾选对应任务

映射关系：

| OpenSpec 任务类型 | 流水线阶段 | 执行者 |
|------------------|-----------|--------|
| 项目初始化 / 结构搭建 | Spec → Design 过渡时由主 agent 完成 | 主 agent |
| 交互设计相关 | Designer | Gemini CLI |
| 代码实现 | Coder | Codex CLI |
| 代码质量检查 | Reviewer | Codex CLI |
| 测试策略 | Test Strategist | 主 agent |
| 测试编写与执行 | Test Executor | Codex CLI |

```
spec-writer → designer → coder → reviewer → test-strategist → test-executor
```

### 阶段规则

1. **Spec** — 主 agent 执行。产出 `docs/specs/{feature}.md`。需用户确认后方可继续。
2. **Design** — 调用 Gemini CLI。读取 spec，产出 `docs/designs/{feature}.md`。
3. **Code** — 调用 Codex CLI。读取 spec + design，产出 `bin/`、`lib/`、`remote/` 下脚本代码。
4. **Review** — 调用 Codex CLI。读取代码 + spec，产出 `docs/reviews/{feature}-{日期}.md`。评审不通过时回退到 Code 阶段。
5. **Test Plan** — 主 agent 执行。读取 spec + 代码，产出 `docs/test-plans/{feature}.md`。
6. **Test Exec** — 调用 Codex CLI。读取测试策略 + 代码，产出 `tests/` 下测试文件。全部通过方可结束。

### 阶段信号

每个阶段启动时，主 agent **必须**输出对应的信号 banner，用于标识当前工作流位置：

**阶段启动：**
```
╔══════════════════════════════════════╗
║  📋 SPEC-WRITER                     ║
║  ── 需求 → 规范 ──                   ║
╚══════════════════════════════════════╝

╔══════════════════════════════════════╗
║  🎨 DESIGNER                        ║
║  ── 规范 → 设计 ──                   ║
╚══════════════════════════════════════╝

╔══════════════════════════════════════╗
║  ⚙️ CODER                            ║
║  ── 设计 → 代码 ──                   ║
╚══════════════════════════════════════╝

╔══════════════════════════════════════╗
║  🔍 REVIEWER                        ║
║  ── 代码 → 评审 ──                   ║
╚══════════════════════════════════════╝

╔══════════════════════════════════════╗
║  🧪 TEST-STRATEGIST                 ║
║  ── 代码 → 测试策略 ──               ║
╚══════════════════════════════════════╝

╔══════════════════════════════════════╗
║  🚀 TEST-EXECUTOR                   ║
║  ── 策略 → 测试执行 ──               ║
╚══════════════════════════════════════╝
```

**阶段转换（上一阶段通过）：**
```
  ✅ {上游AGENT} 完成 ─────▶ {下游EMOJI} {下游AGENT} 启动
```

**评审回退：**
```
  ❌ REVIEW 不通过 ─────▶ 🔄 回退 CODER
```

**流水线完成：**
```
══════════════════════════════════════
  🏁 流水线完成 ── 全部阶段通过
══════════════════════════════════════
```

### 命令说明

执行 Bash 命令时，主 agent **必须**在命令调用**之前**输出一个知识 tip banner，帮助用户理解**这条命令在解决什么问题、为什么用这种方式**。目的是让执行过程具有知识传递价值，用户能从中学习。

**banner 必须作为文本消息输出**（不是 Bash 工具的 description 参数），确保用户在界面上能直接看到。

**格式：**
```
┌─ 💡 ──────────────────────────────────────
│  {一句话说明，侧重"为什么"而非"是什么"}
└───────────────────────────────────────────
```

**原则：**
- 说清这一步**在解决什么问题** — 不要解释具体命令或 flag 的用法，用户可以自己查
- 站在流水线视角 — 这步为什么出现在这里、它的产出给谁用
- 一句话足够 — banner 里只放一行核心意图
- 每个 Bash 调用前都要输出 banner — 不能省略

**示例：**

```
┌─ 💡 ──────────────────────────────────────
│  静态语法检查，不执行代码即可确认产出
│  无语法错误
└───────────────────────────────────────────
> python3 -c "import ast; ast.parse(...)"

┌─ 💡 ──────────────────────────────────────
│  快速判断 Codex 产出的代码规模是否合理
└───────────────────────────────────────────
> wc -l src/netscope.py src/static/index.html

┌─ 💡 ──────────────────────────────────────
│  在沙箱中执行 Codex，写入范围限定为 src/
└───────────────────────────────────────────
> codex exec --full-auto --skip-git-repo-check -C ./src "..."

┌─ 💡 ──────────────────────────────────────
│  确认 Codex CLI 已安装且版本可用
└───────────────────────────────────────────
> which codex && codex --version
```

**反例（不要这样写）：**
```
┌─ 💡 ──────────────────────────────────────
│  检查 Python 语法            ← 太浅，命令本身就能看出来
└───────────────────────────────────────────

┌─ 💡 ──────────────────────────────────────
│  which 在 PATH 中定位可执行   ← 在解释命令用法，不是在说意图
│  文件
└───────────────────────────────────────────

┌─ 💡 ──────────────────────────────────────
│  --skip-git-repo-check 跳过   ← 在解释 flag，用户可以自己查
│  git 信任目录校验
└───────────────────────────────────────────
```

**例外：** subagent 阶段调用（Codex / Gemini CLI 执行完整阶段任务）已由阶段 banner 说明，不需要重复输出 tip banner。此规则侧重的是**流水线执行过程中穿插的辅助命令**。

### 阶段转换

- 每个阶段完成后检查产出是否满足该 agent 的质量标准
- 上一阶段的产出文件是下一阶段的输入
- Review 不通过 → 回退 Code → 重新 Review

## Agent 替换规则

替换任意 agent 只需替换 `agents/` 下对应的 `.md` 文件，保持输入输出路径约定不变。CLAUDE.md 无需修改。

## 职责分层

本项目采用 AI 层 + 脚本层的分工模型：

| 层 | 职责 | 执行者 |
|----|------|--------|
| AI 层 | 分析项目目录、判断构建可行性、推断默认参数、注册到 projects.yaml、调用构建脚本 | Claude Code |
| 脚本层 | 读取配置、打包构建上下文、SSH 上传、远端 docker build/push、日志留痕 | Shell 脚本 |

脚本层不做任何智能判断，只接受参数并执行。所有"分析"和"决策"由 AI 层完成。

## 目录约定

```
image-builder/             用户使用的工具目录
  build.sh                 统一构建入口
  projects.yaml            项目注册表
  remote.env.example       远端配置模板
  scripts/                 公共函数库 + 远端入口脚本
  logs/                    构建日志（按项目分目录，不纳入版本控制）
agents/              各 agent 角色定义（独立可替换）
docs/
  specs/             OpenSpec 规范文档
  designs/           交互设计文档
  plans/             实现计划与设计文档
  reviews/           评审记录
  test-plans/        测试策略与用例
tests/               测试代码
```

## 文件命名

- Spec: `docs/specs/{feature-name}.md`
- 设计: `docs/designs/{feature-name}.md`
- 评审: `docs/reviews/{feature-name}-{YYYY-MM-DD}.md`
- 测试计划: `docs/test-plans/{feature-name}.md`
- 实现计划: `docs/plans/{YYYY-MM-DD}-{topic}.md`

## CLI 环境

外部 agent 通过 Bash 工具调用 CLI，详细配置见 `docs/cli-setup.md`。

### 前置条件

- Node.js >= 20
- `npm i -g @openai/codex` (Codex CLI)
- `npm i -g @google/gemini-cli` (Gemini CLI)
- 认证：Codex 需 `codex login` 或 `OPENAI_API_KEY`；Gemini 需 Google 登录或 `GEMINI_API_KEY`

### 调用规范

所有 CLI 调用必须使用非交互模式：

- **Codex CLI**: `codex exec --full-auto "prompt"` — 自动审批 + 沙箱写入
- **Gemini CLI**: `gemini -p "prompt" -y` — headless + 自动审批

稳定性要点：
- 显式指定模型 `-m` 避免默认模型变更
- 通过 `-C` (Codex) 限定工作目录
- 通过管道 `cat file.md | codex exec --full-auto -` 传递上下文

## 语言约定

- 文档：中文
- 代码及注释：英文
