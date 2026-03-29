# k8s-deploy-intent 测试计划

## 测试范围

Phase 1 的测试聚焦在脚本层的本地逻辑验证（不依赖远端 SSH 环境）。

## 测试用例

### T1: project-resolver deploy 字段解析

- 解析有 deploy section 的项目（claude-code-hub-neo），验证 DEPLOY_INTENT=k8s, DEPLOY_NAMESPACE=claude-hub 等
- 解析无 deploy section 的项目（claude-code-hub），验证所有 DEPLOY_* 字段为空
- 解析无 deploy section 的项目（vl-demo），验证所有 DEPLOY_* 字段为空
- 现有构建字段（IMAGE_NAME, VERSION 等）不受 deploy 扩展影响

### T2: deploy.sh 参数解析与验证

- 缺少 --project 参数时报错退出
- 缺少 --deploy-dir 参数时报错退出
- --deploy-dir 指向不存在的路径时报错退出
- --deploy-dir 指向空目录（无 YAML 文件）时报错退出
- --deploy-dir 指向含 YAML 的目录时通过验证
- --force 参数正确设置 REQUESTED_FORCE=true

### T3: deploy intent gating

- 项目 deploy.intent=k8s 时允许继续
- 项目无 deploy section 时（DEPLOY_INTENT 为空）归一化为 none 并拒绝
- 项目 deploy.intent=none 时拒绝

### T4: path segment 安全校验

- 正常项目名（如 claude-code-hub-neo）通过
- 空字符串被拒绝
- "." 被拒绝
- ".." 被拒绝
- 含空格的值被拒绝
- 含斜杠的值被拒绝

### T5: 向后兼容

- build.sh 加载 remote.env（含 DEPLOY_* 字段）后，构建流程不受影响
- build.sh 加载 remote.env（不含 DEPLOY_* 字段）后，构建流程不受影响
- project-resolver 解析旧项目时所有原有字段正确

### T6: 文件结构验证

- deploy-conventions.md 存在且非空
- projects/claude-code-hub-neo.md 存在且非空
- deploys/.gitignore 存在
- deploy.sh 可执行
- scripts/deploy-remote-exec.sh 存在
- scripts/remote-deploy-entry.sh 存在

## 不在本地测试范围

- SSH/SCP 远端推送（需要实际 deploy host）
- 远端目录结构验证（需要实际 deploy host）
- remote-deploy-entry.sh 远端执行（Phase 2 范畴）
