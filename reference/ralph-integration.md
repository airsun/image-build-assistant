# Ralph-loop 集成配置

dan-ultra-workflow 中 Ralph-loop 的 scratchpad 格式、场景模板和配置建议。

---

## Scratchpad 格式规范

Ralph-loop 通过 `.ralph/scratchpad.md` 驱动。文件格式：

```markdown
---
iteration: 1
max_iterations: <N>
completion_promise: "<TEXT>" 或 null
started_at: "<ISO8601>"
---

<任务 prompt>
```

- `iteration`: 当前迭代轮次，stop hook 自动递增
- `max_iterations`: 最大迭代次数（0 = 无限制，建议设安全上限）
- `completion_promise`: 完成标志文本，agent 输出 `<promise>TEXT</promise>` 时循环结束。设为 `null` 则仅按 max_iterations 停止
- `started_at`: 循环启动时间

---

## 场景模板

### 通用模式

适用于任意 task 的迭代开发，agent 按 prompt 自主推进。

```markdown
---
iteration: 1
max_iterations: 8
completion_promise: "TASK_COMPLETE"
started_at: "{{timestamp}}"
---

## 任务
{{task_description}}

## 上下文
- 功能规格：{{spec_path}}
- 设计方案：{{design_path}}

## 完成标准
{{completion_criteria}}

当以上标准全部满足时，输出 <promise>TASK_COMPLETE</promise>。

## 工作记录
（每轮迭代在此追加进展和发现）
```

**配置建议：**
- `max_iterations`: 8（通用场景足够）
- `completion_promise`: 明确可判断的完成条件

---

### Gemini 视觉循环模式

适用于 `[frontend]` + `[complex]` 或有 `[design:...]` 的前端 task，结合截屏验证。

```markdown
---
iteration: 1
max_iterations: 12
completion_promise: "VISUAL_MATCH"
started_at: "{{timestamp}}"
---

## 任务
实现并迭代打磨以下前端组件/页面，直到视觉效果与设计稿一致。

## 设计参照
{{design_reference}}

## 功能规格
{{spec_excerpt}}

## 每轮迭代步骤
1. 检查当前代码状态
2. 使用 Browser MCP 截屏当前页面
3. 与设计参照对比，列出差异
4. 修复差异项
5. 如果所有差异已修复且视觉一致，输出 <promise>VISUAL_MATCH</promise>

## 差异记录
（每轮记录发现的差异和修复情况）
```

**配置建议：**
- `max_iterations`: 12（视觉迭代可能需要更多轮次）
- `completion_promise`: `VISUAL_MATCH`

---

### TDD 模式

适用于需要测试驱动开发的 task。

```markdown
---
iteration: 1
max_iterations: 10
completion_promise: "ALL_TESTS_PASS"
started_at: "{{timestamp}}"
---

## 任务
以 TDD 方式实现以下功能。

## 功能规格
{{spec_excerpt}}

## 每轮迭代步骤
1. 如果没有测试文件，先编写测试
2. 运行测试，检查失败项
3. 编写/修改代码让失败测试通过
4. 运行全部测试
5. 如果全部通过，输出 <promise>ALL_TESTS_PASS</promise>

## 测试命令
{{test_command}}

## 进展记录
（每轮记录测试结果和代码修改）
```

**配置建议：**
- `max_iterations`: 10
- `completion_promise`: `ALL_TESTS_PASS`

---

## 配置建议汇总

| 场景 | max_iterations | completion_promise | 说明 |
|------|---------------|-------------------|------|
| 通用开发 | 8 | `TASK_COMPLETE` | 一般 3-5 轮完成 |
| 视觉迭代 | 12 | `VISUAL_MATCH` | 视觉微调可能需要更多轮 |
| TDD | 10 | `ALL_TESTS_PASS` | 红绿重构循环 |
| 探索/调研 | 5 | null | 无明确完成条件，到次数停 |

**安全提示：**
- 始终设置 `max_iterations` 作为安全网（建议不超过 20）
- `completion_promise` 应是 agent 可客观判断的条件
- 如需中途停止：删除 `.ralph/scratchpad.md`

---

## Cursor Stop Hook 工作原理

Ralph-loop 依赖 `.cursor/hooks.json` 中注册的 stop hook：

```json
{
  "version": 1,
  "hooks": {
    "stop": [{
      "command": ".cursor/hooks/ralph-stop.sh",
      "loop_limit": null
    }]
  }
}
```

**流程：**
1. Agent 完成一轮工作 → Cursor 触发 stop hook
2. `ralph-stop.sh` 检查 `.ralph/scratchpad.md` 是否存在
3. 存在 → 递增 iteration，构造 followup_message 回传给 agent
4. Agent 看到 `🔄 Ralph iteration N` 前缀，继续执行 prompt
5. 循环直到：promise 匹配 / max_iterations 达到 / scratchpad 被删除

**`loop_limit: null`** 很关键——Cursor 默认 loop_limit=5，设为 null 允许无限 hook 循环（实际由 max_iterations 控制）。
