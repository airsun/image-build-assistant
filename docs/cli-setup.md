# CLI 环境配置与测试指南

一步步完成 Codex CLI 和 Gemini CLI 的安装、认证、验证和冒烟测试。

---

## 1. 前置条件

| 依赖 | 最低版本 | 检查命令 |
|------|---------|---------|
| Node.js | >= 20 | `node --version` |
| npm | >= 9 | `npm --version` |

---

## 2. 安装 CLI

```bash
npm install -g @openai/codex
npm install -g @google/gemini-cli
```

验证安装：

```bash
codex --version    # 期望: codex-cli 0.1xx.x
gemini --version   # 期望: 0.2x.x
```

如遇权限问题，使用 `sudo npm install -g` 或配置 npm prefix。

---

## 3. 认证配置

### 3.1 Codex CLI

**方式 A — ChatGPT 账号登录（推荐）：**

```bash
codex login
```

按提示在浏览器中完成 OAuth 授权。

**方式 B — API Key：**

```bash
export OPENAI_API_KEY="sk-..."
```

建议写入 shell 配置文件（`~/.zshrc` 或 `~/.bashrc`）持久化：

```bash
echo 'export OPENAI_API_KEY="sk-..."' >> ~/.zshrc
source ~/.zshrc
```

**方式 C — 自定义端点（代理/中转）：**

编辑 `~/.codex/config.toml`：

```toml
model_provider = "custom"
model = "gpt-5.3-codex"

[model_providers.custom]
name = "custom"
wire_api = "responses"
requires_openai_auth = true
base_url = "http://127.0.0.1:15721/v1"
```

### 3.2 Gemini CLI

**方式 A — Google 账号登录（推荐）：**

```bash
gemini
```

首次运行会打开浏览器完成 OAuth。完成后退出即可。

**方式 B — API Key：**

```bash
export GEMINI_API_KEY="..."
```

持久化：

```bash
echo 'export GEMINI_API_KEY="..."' >> ~/.zshrc
source ~/.zshrc
```

---

## 4. 冒烟测试

逐条运行，确认每个 CLI 均可正常工作。

### 4.1 Codex — 基础调用

```bash
codex exec --full-auto "echo hello from codex"
```

**预期：** 正常执行并返回结果，无报错。

### 4.2 Codex — 管道输入

```bash
echo "Explain this in one sentence: hello world" | codex exec --full-auto -
```

**预期：** Codex 读取 stdin 内容并回复。

### 4.3 Codex — 指定工作目录

```bash
codex exec --full-auto -C ./src "List all files in this directory"
```

**预期：** 列出 `src/` 下的文件（如果 src/ 不存在会报错，属正常）。

### 4.4 Gemini — 基础调用

```bash
gemini -p "Say hello in one sentence" -y
```

**预期：** 返回一句问候，无交互提示。

### 4.5 Gemini — 指定模型

```bash
gemini -p "What is 2+2?" -y -m gemini-3-pro
```

**预期：** 返回 4，确认模型参数生效。

### 4.6 Gemini — 文件上下文

```bash
gemini -p "Summarize this file in one sentence: $(cat CLAUDE.md)" -y
```

**预期：** 返回对 CLAUDE.md 的摘要。

---

## 5. 流水线集成测试

验证 CLI 在本项目流水线中的实际调用方式。

### 5.1 模拟 Designer 阶段（Gemini）

```bash
# 先确保有一个 spec 文件可用
mkdir -p docs/specs
cat > docs/specs/_smoke-test.md << 'EOF'
# Smoke Test Feature

## 功能描述
一个简单的按钮，点击后显示 "Hello"。

## 验收标准
- 页面上有一个按钮
- 点击按钮后显示 "Hello" 文本
EOF

# 调用 Gemini 产出设计
mkdir -p docs/designs
gemini -p "根据以下 spec 文档产出交互设计方案，输出为 markdown 格式。

$(cat docs/specs/_smoke-test.md)" \
  -y -m gemini-3-pro > docs/designs/_smoke-test.md

# 检查产出
cat docs/designs/_smoke-test.md
```

**预期：** `docs/designs/_smoke-test.md` 包含交互设计内容。

### 5.2 模拟 Coder 阶段（Codex）

```bash
mkdir -p src

codex exec --full-auto -C ./src \
  "基于以下 spec 和设计文档实现功能代码，创建一个简单的 HTML 文件。

Spec:
$(cat docs/specs/_smoke-test.md)

Design:
$(cat docs/designs/_smoke-test.md)"

# 检查产出
ls src/
```

**预期：** `src/` 下出现新文件。

### 5.3 模拟 Reviewer 阶段（Codex）

```bash
mkdir -p docs/reviews

codex exec --full-auto \
  "评审 src/ 下的代码，对照以下 spec 检查一致性、质量和安全性，输出结构化评审报告，包含通过/不通过结论。

Spec:
$(cat docs/specs/_smoke-test.md)" > docs/reviews/_smoke-test-$(date +%Y-%m-%d).md

# 检查产出
cat docs/reviews/_smoke-test-$(date +%Y-%m-%d).md
```

**预期：** 评审报告包含问题列表和结论。

### 5.4 清理测试文件

```bash
rm -f docs/specs/_smoke-test.md
rm -f docs/designs/_smoke-test.md
rm -f docs/reviews/_smoke-test-*.md
# src/ 下的测试产出按需手动清理
```

---

## 6. 常见问题

| 现象 | 原因 | 解决 |
|------|------|------|
| `codex: command not found` | 未安装或 PATH 缺失 | `npm i -g @openai/codex`，确认 `npm bin -g` 在 PATH 中 |
| `gemini: command not found` | 未安装或 PATH 缺失 | `npm i -g @google/gemini-cli`，确认 PATH |
| Codex 报 401/403 | API Key 无效或过期 | `codex login` 重新认证，或检查 `OPENAI_API_KEY` |
| Gemini 报认证错误 | OAuth token 过期 | 运行 `gemini` 重新登录 |
| Codex 挂起无响应 | 网络问题或模型不可用 | 检查网络；加 `timeout 120` 前缀限时 |
| Gemini `-p` 模式仍弹交互 | 缺少 `-y` 参数 | 命令末尾加 `-y` 自动审批 |
| `exec` 无写入权限 | 沙箱限制 | 使用 `--full-auto` 启用沙箱写入 |
| 自定义端点连接失败 | base_url 错误或服务未启动 | 检查 `~/.codex/config.toml` 中 `base_url` 和本地服务状态 |

---

## 7. 参考调用模板

流水线各阶段的标准调用命令，复制即用：

```bash
# Designer (Gemini)
gemini -p "根据以下 spec 文档产出交互设计方案，输出为 markdown 格式。\n\n$(cat docs/specs/{feature}.md)" \
  -y -m gemini-3-pro > docs/designs/{feature}.md

# Coder (Codex)
codex exec --full-auto -C ./src \
  "基于以下 spec 和设计文档实现功能代码。\n\nSpec:\n$(cat docs/specs/{feature}.md)\n\nDesign:\n$(cat docs/designs/{feature}.md)"

# Reviewer (Codex)
codex exec --full-auto \
  "评审 src/ 下的代码，对照以下 spec 检查一致性、质量和安全性，输出结构化评审报告。\n\nSpec:\n$(cat docs/specs/{feature}.md)" \
  > docs/reviews/{feature}-$(date +%Y-%m-%d).md

# Test Executor (Codex)
codex exec --full-auto \
  "根据以下测试计划编写测试代码并运行，测试文件放在 tests/ 目录下。\n\nTest Plan:\n$(cat docs/test-plans/{feature}.md)"
```

将 `{feature}` 替换为实际功能名称即可。
