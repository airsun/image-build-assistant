# k8s-deploy-intent 代码评审

日期：2026-03-27

## 评审结论

不通过

## 评审范围

- `deploy.sh`
- `scripts/deploy-remote-exec.sh`
- `scripts/remote-deploy-entry.sh`
- `scripts/project-resolver.sh`
- `build.sh`
- `projects.yaml`
- `remote.env.example`

## 问题列表

### [严重] 未限制仅 `deploy.intent: k8s` 的项目进入部署流程
- 文件：`deploy.sh`、`scripts/project-resolver.sh`
- 位置：`deploy.sh:105-137`；`scripts/project-resolver.sh:158-164`
- 描述：`deploy.sh` 只校验项目存在和 `--deploy-dir` 存在，没有校验 `DEPLOY_INTENT` 是否为 `k8s`。这意味着没有 `deploy` section 的旧项目，或显式标记为 `none` 的项目，也可以被直接推送到 deploy host。参考规范要求未声明 `deploy` 的项目等同于 `intent: none`，不应触发部署流程。
- 建议：在 `resolve_project_by_name` 之后显式校验 `DEPLOY_INTENT`；空值按规范归一化为 `none`，仅允许 `k8s` 继续执行，其余场景直接报错退出。

### [中等] 远端目录已存在时没有“是否覆盖”交互，直接失败
- 文件：`scripts/deploy-remote-exec.sh`、`deploy.sh`
- 位置：`scripts/deploy-remote-exec.sh:49-53`；`deploy.sh:136-138`
- 描述：规范要求当远端 `{project}/{version}` 目录已存在时，系统提示已存在并询问是否覆盖。当前实现检测到目录存在后直接返回错误，调用方也没有交互确认或 `--force` 之类的覆盖开关，和规范场景不一致。
- 建议：在 `deploy.sh` 层增加交互确认，或提供显式的 `--force` 参数；确认覆盖时需要先安全清空目标目录，再执行推送。

### [中等] 推送成功后没有回写 `deployed_version` / `deployed_commit`
- 文件：`deploy.sh`、`scripts/project-resolver.sh`、`projects.yaml`
- 位置：`deploy.sh:136-138`；`scripts/project-resolver.sh:163-164`；`projects.yaml:23-29`
- 描述：规范将 `deployed_version` 和 `deployed_commit` 定义为“由系统回写”的字段，但本次改动只实现了解析，没有任何成功推送后的写回逻辑。这样会导致 `projects.yaml` 无法记录“最近一次成功推送/部署”的状态，与规范不一致，也削弱审计价值。
- 建议：在部署目录成功推送后原子更新 `projects.yaml` 中目标项目的 `deployed_version` 和 `deployed_commit`，同时处理无 `deploy` section 的旧项目兼容性。

### [中等] `--deploy-dir` 只校验“是目录”，未校验目录内容是否符合部署产物约定
- 文件：`deploy.sh`
- 位置：`deploy.sh:108-117`
- 描述：当前只要 `--deploy-dir` 指向一个存在的目录就会继续推送，没有检查目录内是否包含 `*.yaml` 和 `deploy-note.md`，也没有确认目录 basename 是否确实代表目标版本。这样会把错误目录、空目录或混入无关文件的目录原样推送到 deploy host，和规范中的远端目录结构约定不一致。
- 建议：至少校验目录中存在一个 YAML 文件和 `deploy-note.md`；必要时校验目录名与目标版本字段一致，并在错误时给出明确提示。

### [中等] 远端路径与 SSH/SCP 参数缺少特殊字符约束，存在越界和兼容性风险
- 文件：`deploy.sh`、`scripts/deploy-remote-exec.sh`、`scripts/remote-deploy-entry.sh`
- 位置：`deploy.sh:131-134`；`scripts/deploy-remote-exec.sh:15-25`、`55-61`；`scripts/remote-deploy-entry.sh:34-35`
- 描述：远端目标路径由 `DEPLOY_BASE_DIR`、`PROJECT_NAME` 和 `basename(--deploy-dir)` 直接拼接，未拒绝 `.`、`..`、绝对路径片段或空白字符。若项目名配置异常，可能把文件写到 `DEPLOY_BASE_DIR` 之外。另一个问题是 SSH/SCP 选项通过命令替换展开，`DEPLOY_SSH_KEY_PATH` 或相关路径包含空格时会发生词拆分，推送流程会异常。
- 建议：对项目名、版本目录名和基础路径做 path-segment 校验；SSH/SCP 参数改为数组构造，避免命令替换和词拆分。

### [轻微] `remote-deploy-entry.sh` 当前未接入主流程，维护收益不足
- 文件：`scripts/remote-deploy-entry.sh`、`scripts/deploy-remote-exec.sh`
- 位置：`scripts/remote-deploy-entry.sh:14-39`；`scripts/deploy-remote-exec.sh:39-63`
- 描述：当前部署流程直接执行远端 `mkdir` + `scp`，不会上传或执行 `remote-deploy-entry.sh`。该脚本目前既不参与实际路径准备，也不承担额外校验、日志或审计职责，属于未接线代码，和现有 `remote-build-entry.sh` 的模式也不一致。
- 建议：如果 Phase 1 不需要远端入口脚本，应删除该文件以减少维护面；如果保留，应真正接入 `deploy.sh` 调用链，并让它承担目录准备、文件校验或接收确认职责。

## 优点

- `build.sh` 新增 `DEPLOY_*` 配置加载时没有把它们纳入现有构建必填项，现有仅构建场景基本不受影响，向后兼容性总体可接受。
- `scripts/project-resolver.sh` 在清理状态时同步清理了 `BUILD_ARGS` 和部署相关变量，避免多次调用之间出现脏状态串值。
- `remote.env.example` 和 `projects.yaml` 已经把 Deploy Host / deploy section 的主要字段补齐，便于后续联调和文档落地。
- `deploy.sh` 与 `scripts/deploy-remote-exec.sh` 做了职责拆分，整体结构与现有 `build.sh` / `remote-exec.sh` 的组织方式一致。

## 总结

本次变更把部署推送链路的骨架搭起来了，且没有明显破坏现有 `build.sh` 的构建流程；但按参考规范核对，当前实现仍缺少几个关键闭环：部署意图 gating、重复推送覆盖确认、推送成功后的状态回写，以及对部署目录和路径参数的更严格校验。建议先补齐这些问题，再判定为通过。
