## 1. 脚本层改动 [backend] [simple]

- [x] 1.1 `build.sh` — `build_image_load_remote_config()` 中移除 HARBOR_HOST 必填校验，改为可选赋默认空值
- [x] 1.2 `remote-build-entry.sh` — `remote_entry_run_build()` 中 tag 拼接增加条件：HARBOR_HOST 有值用完整路径，为空用纯 IMAGE_NAME
- [x] 1.3 `remote-build-entry.sh` — push 条件从 `PUSH == true` 改为 `PUSH == true && HARBOR_HOST 非空`

## 2. 配置更新 [backend] [simple]

- [x] 2.1 `remote.env.example` — 标注 HARBOR_HOST、HARBOR_PROJECT 为可选，说明无 Harbor 场景
- [x] 2.2 `home-134.env` — 填入正确的连接信息，不含 HARBOR_HOST，PUSH=false
