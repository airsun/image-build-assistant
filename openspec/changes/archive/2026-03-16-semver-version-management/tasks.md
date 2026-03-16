## 1. 脚本层：解析与传参

- [x] 1.1 project-resolver.sh 新增解析 version 和 built_commit 字段，设置 VERSION 和 BUILT_COMMIT 变量
- [x] 1.2 build.sh 的 build_image_merge_settings 中移除时间戳 fallback，VERSION 来源改为 --version 参数 > yaml version 字段
- [x] 1.3 project-resolver.sh 的 project_resolver_clear 中初始化 VERSION 和 BUILT_COMMIT 为空

## 2. AI 层：版本决策逻辑

- [x] 2.1 构建前读取 projects.yaml 的 version 和 built_commit
- [x] 2.2 获取目标仓库 HEAD commit hash 并与 built_commit 对比
- [x] 2.3 实现决策分支：首次构建 / 有变更自动 bump / 无变更默认不构建 / 用户坚持则 bump
- [x] 2.4 实现版本倒退防护：用户指定版本时校验必须大于当前版本
- [x] 2.5 将决定的版本号通过 --version 参数传给 build.sh

## 3. 构建后回写

- [x] 3.1 构建成功后更新 projects.yaml 的 version 和 built_commit 字段
