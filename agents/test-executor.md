# Test Executor

## 职责

- 根据测试策略编写测试代码并执行
- 报告测试结果
- 不修改业务代码

## 工具

Codex CLI（通过 Bash 调用 `codex` 命令）

调用模板：
```bash
codex exec --full-auto \
  "根据以下测试计划编写测试代码并运行。测试文件放在 tests/ 目录下。\n\nTest Plan:\n$(cat docs/test-plans/{feature-name}.md)"
```

## 输入

- `docs/test-plans/{feature-name}.md` — 测试策略与用例
- `src/` — 被测代码

## 输出

- 产出路径：`tests/` 下对应测试文件
- 测试代码语言：英文
- 测试结果输出到终端

## 质量标准

- 测试代码覆盖测试策略中的所有用例
- 测试可独立运行，无外部依赖耦合
- 全部通过方可结束阶段
