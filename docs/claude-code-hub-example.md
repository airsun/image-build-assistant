# `claude-code-hub` 接入示例

`claude-code-hub` 是当前独立镜像构建助手中的第一个注册项目。

## 注册信息

对应的 `projects.yaml` 条目为：

```yaml
projects:
  - name: claude-code-hub
    source_dir: ../../claude-code-hub
    dockerfile_path: deploy/Dockerfile
    build_context: .
    image_name: claude-code-hub
    harbor_project: library
    platform: linux/amd64
    enabled: true
```

## 含义说明

- `source_dir`：指向真实源码目录 `claude-code-hub`
- `dockerfile_path`：使用 `deploy/Dockerfile`
- `build_context`：使用项目根目录 `.` 作为构建上下文
- `image_name`：镜像名为 `claude-code-hub`
- `harbor_project`：默认推送到 `library`

## 执行方式

```bash
bash image-build-assistant/bin/build-image.sh --project claude-code-hub
```

如需临时覆盖版本：

```bash
bash image-build-assistant/bin/build-image.sh \
  --project claude-code-hub \
  --version v1.0.0
```

## 备注

- `Harbor` 登录在远端完成
- 远端构建前会清理本次运行对应的代码工作区
- Docker layer cache 保持正常复用
