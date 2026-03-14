## 1. 清理废弃文件

- [x] 1.1 删除 `deploy/` 目录（`remote-build.sh`、`remote-build-entry.sh`、`remote-build.env.example`）
- [x] 1.2 删除 `src/` 空目录
- [x] 1.3 删除 `tests/remote-build-compat.test.sh` 兼容性测试

## 2. 提升嵌套目录到根

- [x] 2.1 将 `image-build-assistant/bin/` 移动到根 `bin/`
- [x] 2.2 将 `image-build-assistant/lib/` 移动到根 `lib/`
- [x] 2.3 将 `image-build-assistant/config/` 移动到根 `config/`
- [x] 2.4 将 `image-build-assistant/remote/` 移动到根 `remote/`
- [x] 2.5 将 `image-build-assistant/tests/*.test.sh` 合并到根 `tests/`
- [x] 2.6 将 `image-build-assistant/docs/usage.md` 和 `claude-code-hub-example.md` 合并到根 `docs/`
- [x] 2.7 删除空的 `image-build-assistant/` 嵌套目录

## 3. 修复路径引用

- [x] 3.1 更新 `bin/build-image.sh` 中的 `BUILD_IMAGE_ASSISTANT_ROOT` 路径计算（从 `bin/..` 到项目根）
- [x] 3.2 更新 `config/projects.yaml` 中 `source_dir` 的相对路径（从 `../../claude-code-hub` 调整为扁平化后的正确路径）
- [x] 3.3 更新 `lib/remote-exec.sh` 中的 `REMOTE_EXEC_SCRIPT_DIR` 默认路径
- [x] 3.4 逐一检查所有 `tests/*.test.sh` 中的路径引用并修复

## 4. 新增构建日志能力

- [x] 4.1 在 `bin/build-image.sh` 的 `build_image_main` 中新增日志目录创建和 tee 逻辑
- [x] 4.2 日志文件名格式 `logs/{project-name}/{YYYYMMDD}-{HHMMSS}.log`
- [x] 4.3 确保 stdout 和 stderr 同时输出到终端和日志文件
- [x] 4.4 在 `.gitignore` 中添加 `logs/` 排除规则

## 5. 更新文档和配置

- [x] 5.1 更新 `CLAUDE.md` 中的目录约定部分，反映扁平化后的结构
- [x] 5.2 在 `CLAUDE.md` 中增加 AI 层/脚本层职责分工说明
- [x] 5.3 更新 `docs/usage.md` 中的路径示例

## 6. 验证

- [x] 6.1 运行全部 tests，确认路径修复后测试通过
- [x] 6.2 确认 `bin/build-image.sh --help` 或基本参数解析正常工作（dry run）
