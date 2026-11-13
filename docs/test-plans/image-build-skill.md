# 测试策略：image-build 技能（双上下文构建）

> 对应规范：`docs/specs/image-build-skill.md`
> 测试文件：`tests/setup-skill.test.sh`（新增）、`tests/assistant-layout.test.sh`（扩展）
> 环境：纯本地 bash，无网络依赖（安装脚本只做文件操作，天然隔离；AI 层文本断言为 grep 标记检查）

## 测试层次与范围

| 层 | 覆盖 | 手段 |
|----|------|------|
| 布局层 | 新文件存在性（双份 SKILL.md、setup 脚本、spec）+ 双份逐字节一致 + 结构标记 + 无离仓相对路径 | 扩展 assistant-layout.test.sh |
| 安装层 | setup-skill.sh 全部行为（symlink 幂等/保护、config、dry-run、flags、脱离仓库） | tests/setup-skill.test.sh（假 HOME + 假 IB 夹具） |
| AI 层文本 | SKILL.md 承载解析链/签名/脚本调用的结构性标记 | layout 测试 grep 断言（4 个结构性词） |

## 关键用例（按风险排序）

### 1. 安装脚本（tests/setup-skill.test.sh，11 用例）

| # | 用例 | 断言要点 |
|---|------|---------|
| 1 | 全新安装 | 双 symlink 指向夹具内绝对路径、经 symlink 可读 SKILL.md、config home 内容正确 |
| 2 | 幂等重跑 | exit 0，symlink/config 均未变 |
| 3 | symlink 指向别处（无 --force） | exit 非 0，stderr 含 `--force` 提示，原链接未替换 |
| 4 | `--force` | 指向别处的链接被替换，exit 0 |
| 5 | 目标是普通目录 | exit 非 0，哨兵文件完好（绝不删除） |
| 6 | 父目录缺失 | `~/.claude/skills`、`~/.cursor/skills` 自动创建 |
| 7 | `--dry-run` | exit 0，无任何 symlink/config 产生 |
| 8 | 脚本脱离仓库运行 | exit 非 0，stderr 含 `missing` 提示 |
| 9 | `--with-shell-export` | `.zshrc` 恰好 1 行 export；重跑不重复追加 |
| 10 | `--skip-claude` | 仅 cursor 侧安装 |
| 11 | config 已存在不同内容 | 覆盖为新值 |

### 2. 布局断言（assistant-layout.test.sh 扩展）

- required_paths 新增：双份 `image-build/SKILL.md`、`setup-skill.sh`、`docs/specs/image-build-skill.md`
- `cmp -s` 双份 SKILL.md 逐字节一致（防漂移）
- grep 结构标记（只测 .claude 份，cmp 保证另一份同值）：`IMAGE_BUILD_HOME`、`setup-skill.sh`、`remote.env.example`、`k8s-deploy-intent.md`
- 反向断言：不含 `../../../docs/specs`（防 oss-image-build 式离仓失效相对路径复发）

## 不覆盖（明示边界）

- 真实 ssh / docker build：需要内网 builder，由真机验证（可选冒烟）
- 目标会话中技能实际加载与触发：依赖会话重启后的技能发现，真会话验证
- GUI 启动会话的 config 路径命中：机制已推演，未在 GUI 会话实测
- 并发写 projects.yaml 竞态：v1 明确不处理

## 通过标准

- `tests/setup-skill.test.sh` 11 用例全通过
- `tests/assistant-layout.test.sh` 扩展断言全通过
- 存量回归测试全部保持通过
