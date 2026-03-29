# Codex CLI Prompt 模板

dan-ultra-workflow 研发阶段使用的 Codex CLI prompt 模板。每个模板包含 `{{变量}}` 占位符，由编排 skill 在运行时填入实际内容。

---

## 技术评审 Prompt

用于研发阶段步骤 1：评估 design 和 spec 的技术可行性。

**调用方式：**
```bash
codex exec -m gpt-5 --full-auto --sandbox workspace-read "{{prompt}}"
```

**模板：**
```
你是一位资深技术架构师，请对以下功能的设计方案进行技术评审。

## 评审维度
1. 架构合理性 — 模块划分、依赖方向、扩展性
2. 安全风险 — 输入校验、认证授权、数据保护
3. 性能隐患 — 热点路径、N+1 查询、内存占用
4. API 设计一致性 — 与已有接口风格统一
5. 任务拆分质量 — tasks.md 中的任务是否可独立执行、粒度是否合适

## 设计文档
{{design_content}}

## 功能规格
{{spec_content}}

## 任务列表
{{tasks_content}}

## 输出格式
请输出结构化评审报告：
- 每个维度给出 ✅ 通过 / ⚠️ 关注 / ❌ 需修改
- 每个问题附具体位置和修改建议
- 最后给出总体结论：通过 / 有条件通过 / 不通过
```

---

## 代码评审 Prompt

用于研发阶段步骤 3：所有 tasks 完成后对代码进行评审。

**调用方式：**
```bash
codex exec -m gpt-5 --full-auto --sandbox workspace-read "{{prompt}}"
```

**模板：**
```
你是一位代码评审专家，请评审以下代码变更，对照功能规格检查一致性、质量和安全性。

## 功能规格
{{spec_content}}

## 设计方案
{{design_content}}

## 评审范围
以下文件在本次变更中被新增或修改：
{{changed_files}}

## 评审维度
1. 功能一致性 — 代码是否实现了 spec 中的所有要求
2. 代码质量 — 可读性、命名、结构、重复代码
3. 安全性 — 输入校验、SQL注入、XSS、敏感信息泄露
4. 错误处理 — 异常路径是否覆盖
5. 测试充分性 — 核心路径是否有测试覆盖

## 输出格式
- 问题列表，每个问题含：文件:行号、严重程度（Critical/Warning/Suggestion）、描述、修改建议
- 总体结论：通过 / 不通过（附必须修复项）
```

---

## 后端任务执行 Prompt

用于 `[backend]` 类型 task 的 Codex 执行。

**调用方式：**
```bash
codex exec -m gpt-5 --full-auto --sandbox workspace-write "{{prompt}}"
```

`[simple]` 任务可建议快速模型（由用户确认后切换 `-m` 参数）。

**模板：**
```
基于以下规格和设计实现指定的后端任务。

## 当前任务
{{task_description}}

## 功能规格（相关部分）
{{spec_excerpt}}

## 设计方案（相关部分）
{{design_excerpt}}

## 项目上下文
- 技术栈：{{tech_stack}}
- 代码风格：遵循项目现有约定
- 输出目录：{{output_dir}}

## 约束
- 只实现当前任务描述的内容，不扩展范围
- 遵循设计方案中的 API 接口契约
- 代码可编译/运行，无语法错误
- 变量名和函数名使用英文
```

---

## 变量说明

| 变量 | 来源 | 说明 |
|------|------|------|
| `{{design_content}}` | `openspec/changes/<name>/design.md` | 完整设计文档 |
| `{{spec_content}}` | `openspec/changes/<name>/specs/**/*.md` | 拼接所有 spec |
| `{{tasks_content}}` | `openspec/changes/<name>/tasks.md` | 完整任务列表 |
| `{{changed_files}}` | `git diff --name-only` 或手动列出 | 本次变更文件 |
| `{{task_description}}` | tasks.md 中当前 task 行 | 单个任务描述 |
| `{{spec_excerpt}}` | 与当前 task 相关的 spec 片段 | 按关键词匹配 |
| `{{design_excerpt}}` | 与当前 task 相关的 design 片段 | 按关键词匹配 |
| `{{tech_stack}}` | 项目实际技术栈 | 如 Node.js/Python/Go |
| `{{output_dir}}` | 任务指定的输出目录 | 如 `src/` |
