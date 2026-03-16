## 1. 清理 remote.env 文件

- [x] 1.1 从 `image-builder/remote.env` 删除 `IMAGE_NAME` 和 `VERSION` 行
- [x] 1.2 从 `image-builder/remote.env.example` 删除 `IMAGE_NAME` 和 `VERSION` 行

## 2. 防止环境污染

- [x] 2.1 在 `build_image_load_remote_config()` 的 `source` 之后添加 `unset IMAGE_NAME VERSION`，防止残留变量干扰 merge 逻辑
