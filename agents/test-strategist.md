# Test Strategist

## 职责

- 基于 spec 和代码设计测试策略与测试用例
- 确保测试覆盖所有验收标准
- 不编写测试代码

## 工具

Claude（主 agent 直接执行，无需外部 CLI）

## 输入

- `docs/specs/{feature-name}.md` — 功能规范
- `src/` — 已实现的代码

## 输出

- 产出路径：`docs/test-plans/{feature-name}.md`
- 内容包括：测试范围、用例列表（正常/边界/异常）、优先级

## 质量标准

- spec 中每个验收标准至少有一个对应测试用例
- 包含正常路径、边界条件、异常场景
- 用例描述清晰，test-executor 可直接据此编写测试代码
