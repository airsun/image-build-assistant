# 远程构建入口迁移说明

原先放在当前项目外层目录中的远程构建脚本，已经迁移到独立目录 `image-build-assistant/`。

## 当前状态

- `deploy/remote-build.sh`：保留为**兼容入口**
- `deploy/remote-build-entry.sh`：已废弃，不再直接执行
- 新的主入口：`image-build-assistant/image-builder/build.sh`

## 推荐用法

优先直接使用独立助手：

```bash
bash image-build-assistant/image-builder/build.sh --project claude-code-hub
```

如果你仍然执行旧入口：

```bash
bash deploy/remote-build.sh
```

它会提示迁移信息，并转发到独立助手来构建 `claude-code-hub`。

## 配置位置

旧入口默认仍会读取：

```bash
deploy/remote-build.env
```

这样可以兼容你当前已经填写好的远端 SSH / Harbor 参数，不需要立刻重填。

新的独立助手文档请优先查看：

- `image-build-assistant/docs/usage.md`
- `image-build-assistant/docs/claude-code-hub-example.md`

## Harbor 登录说明

`Harbor` 登录仍在**远端构建机**完成，不在本地配置文件中保存账号密码。

建议先在远端构建机执行：

```bash
docker login <your-harbor-host>
```

后续独立助手会复用远端当前账号的 Docker 登录态。
