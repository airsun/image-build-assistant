## Context

当前所有远端连接信息（build host、Harbor、deploy host）存储在单个 `image-builder/remote.env` 文件中。`build.sh` 和 `deploy.sh` 默认读取该文件，但已支持 `--config` 参数指定替代路径。`project-resolver.sh` 从 `projects.yaml` 解析项目的构建和部署字段，但不涉及环境路由。

助手现在在 2-3 个不同局域网之间工作，每个网络有独立的基础设施。项目不跨环境构建——一个项目固定属于一个网络环境。

## Goals / Non-Goals

**Goals:**

- 支持多套独立的远端基础设施配置，按环境名隔离
- 项目在 `projects.yaml` 中声明环境归属，构建和部署自动路由
- 向后兼容：未声明 `env` 的项目回退到 `remote.env`
- 脚本层零改动

**Non-Goals:**

- 不支持同一项目跨多环境构建（当前场景不需要）
- 不做环境自动检测（IP 段匹配、hostname 探测等），显式声明更可靠
- 不做环境间的版本同步或镜像复制
- 不改变 `remote.env` 的字段结构（每份 env 文件的内容格式不变）

## Decisions

### D1: 环境配置存放在 `remote-envs/` 目录，每环境一个 `.env` 文件

**选择**：`image-builder/remote-envs/{env-name}.env`

**替代方案**：
- 在 `projects.yaml` 中内联环境配置 → 拒绝：YAML 中混入 SSH 密钥路径等连接细节，职责不清，且同环境多项目需重复配置
- 单个 `remote.env` 用 section 分隔多环境 → 拒绝：需要改脚本层的 `source` 逻辑，违背"脚本层零改动"目标

**理由**：每份 env 文件格式与现有 `remote.env` 完全一致，脚本层的 `source "${config_path}"` 无需改动。新增环境只需添加文件。

### D2: 项目通过 `env` 字段声明归属，而非全局"活跃环境"状态

**选择**：`projects.yaml` 项目条目新增 `env` 字段

**替代方案**：
- 全局活跃环境（软链或状态文件）→ 拒绝：需要"切换"动作，有忘记切换的风险，且无法防止误构建非当前网络的项目
- CLI `--config` 每次手动指定 → 拒绝：AI 层每次构建都要问用户"你在哪个网络"，体验差

**理由**：项目与环境是 1:1 稳定映射，声明一次即可。AI 层构建时读 `env` 字段自动路由，无需额外交互。

### D3: `project-resolver.sh` 解析 `env` 字段

**选择**：在 `project-resolver.sh` 中新增 `ENV_NAME` 变量解析，与其他项目字段同层级

**理由**：`env` 是项目级属性，与 `harbor_project`、`platform` 等同级。resolver 已有成熟的字段解析模式，复用即可。这是本次唯一的脚本层改动点，但改动量极小（一行解析 + 一行 clear）。

### D4: 无 `env` 字段时回退 `remote.env`

**选择**：AI 层路由逻辑：`env` 有值 → `remote-envs/{env}.env`；`env` 为空 → `remote.env`

**理由**：现有项目不需要迁移。可以逐步给项目加 `env` 字段，未加的继续用原有行为。

## Risks / Trade-offs

**[Risk] env 文件不存在或路径拼错** → AI 层在调用 `build.sh --config` 前检查文件存在性，不存在则报错并提示可用的 env 文件列表

**[Risk] env 文件中缺少 DEPLOY_* 字段导致部署失败** → 每份 env 文件应包含 build + harbor + deploy 全套配置。`remote.env.example` 更新为标注"每份 env 文件需包含的完整字段列表"

**[Trade-off] `project-resolver.sh` 有一行改动，不是严格的"脚本层零改动"** → 可接受：改动量极小（新增一个字段解析），不改变任何控制流，且与现有字段解析模式一致
