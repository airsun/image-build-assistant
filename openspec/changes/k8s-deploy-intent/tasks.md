## 1. projects.yaml 扩展与解析

- [x] 1.1 在 projects.yaml 中为现有项目添加 deploy section 示例（claude-code-hub-neo 作为首个 k8s 项目）
- [x] 1.2 扩展 project-resolver.sh，支持解析 deploy section 下的字段（DEPLOY_INTENT、DEPLOY_NAMESPACE、DEPLOY_CLUSTER、DEPLOY_DOMAIN、DEPLOY_CONTAINER_PORT、DEPLOYED_VERSION、DEPLOYED_COMMIT）
- [x] 1.3 确保 project-resolver 对无 deploy section 的项目向后兼容（deploy 字段为空字符串）

## 2. 全局规约文档

- [x] 2.1 创建 image-builder/deploy-conventions.md，定义网络访问、工作负载、镜像拉取、namespace、存储、配置注入的默认规则
- [x] 2.2 在 CLAUDE.md 中补充 AI 层部署流程说明，引用 deploy-conventions.md

## 3. deploy note 机制

- [x] 3.1 创建 image-builder/projects/ 目录
- [x] 3.2 为 claude-code-hub-neo 编写首个 deploy note（projects/claude-code-hub-neo.md），包含项目运行依赖、存储需求、配置注入等信息

## 4. remote.env 扩展

- [x] 4.1 在 remote.env.example 中新增 Deploy Host section（DEPLOY_HOST、DEPLOY_PORT、DEPLOY_USER、DEPLOY_SSH_KEY_PATH、DEPLOY_BASE_DIR）
- [x] 4.2 在 build.sh 的 load_remote_config 逻辑中兼容新字段（deploy 字段可选，缺失不报错）

## 5. YAML 输出目录结构

- [x] 5.1 创建 image-builder/deploys/ 目录并添加 .gitignore（排除生成的 YAML 历史，保留目录结构）
- [x] 5.2 在 docs/specs/ 中整合 k8s-deploy-intent 规范文档，说明 YAML 输出格式和 deploy-note.md 内容要求

## 6. deploy.sh 入口脚本

- [x] 6.1 创建 image-builder/deploy.sh，实现参数解析（--project、--deploy-dir、--config、--projects）
- [x] 6.2 实现 deploy host 配置加载（从 remote.env 读取 DEPLOY_* 字段）
- [x] 6.3 实现 SCP 推送逻辑：将本地 deploy 目录推送到远端 {DEPLOY_BASE_DIR}/{project}/{version}/
- [x] 6.4 实现重复推送检测：远端目录已存在时提示并询问是否覆盖
- [x] 6.5 推送成功后输出远端完整路径

## 7. 远端部署脚本

- [x] 7.1 创建 scripts/deploy-remote-exec.sh，封装 deploy host 的 SSH/SCP 操作（复用 remote-exec.sh 的模式）
- [x] 7.2 创建 scripts/remote-deploy-entry.sh（远端接收脚本），Phase 1 仅做目录准备和文件接收确认

## 8. 集成验证

- [x] 8.1 端到端验证：projects.yaml 配置 → AI 生成 YAML → deploy.sh 推送到远端 → 远端目录结构正确
- [x] 8.2 验证无 deploy intent 的项目不受影响（纯构建流程不变）
