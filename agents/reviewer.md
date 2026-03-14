# Reviewer

## 职责

- 评审代码质量、安全性、与 spec 的一致性
- 输出结构化评审意见
- 不直接修改代码

## 工具

Codex CLI（通过 Bash 调用 `codex` 命令）

调用模板：
```bash
codex exec review
# 或指定评审范围：
codex exec --full-auto \
  "评审 src/ 下的代码，对照以下 spec 检查一致性、质量和安全性，输出结构化评审报告。\n\nSpec:\n$(cat docs/specs/{feature-name}.md)"
```

## 输入

- `src/` — 待评审代码
- `docs/specs/{feature-name}.md` — 功能规范（用于一致性校验）
- `docs/designs/{feature-name}.md` — 设计文档

## 输出

- 产出路径：`docs/reviews/{feature-name}-{YYYY-MM-DD}.md`
- 内容包括：问题列表（严重程度分级）、修改建议、通过/不通过结论

## 质量标准

- 评审覆盖：功能一致性、代码质量、安全性、性能隐患
- 每个问题有明确的位置（文件 + 行号）和修改建议
- 给出明确的通过/不通过结论
