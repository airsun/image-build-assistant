## Context

`build.sh` 在 `build_image_load_remote_config()` 中强制校验 HARBOR_HOST 非空。`remote-build-entry.sh` 的 `remote_entry_run_build()` 用 `${HARBOR_HOST}/${HARBOR_PROJECT}/${IMAGE_NAME}` 拼接镜像 tag，无条件依赖 Harbor。

新增的 home-134 环境是"构建即运行"模型，无 Harbor，镜像本机使用。

## Goals / Non-Goals

**Goals:**

- HARBOR_HOST 变为可选，无值时构建仍正常工作
- 无 Harbor 时镜像 tag 简化为 `IMAGE_NAME:VERSION`
- 无 Harbor 时自动跳过 push，无论 PUSH 设为什么值

**Non-Goals:**

- 不引入 local registry 或其他替代方案
- 不改变有 Harbor 时的任何行为

## Decisions

### D1: tag 拼接策略

HARBOR_HOST 有值 → `${HARBOR_HOST}/${HARBOR_PROJECT}/${IMAGE_NAME}`
HARBOR_HOST 为空 → `${IMAGE_NAME}`

在 `remote-build-entry.sh` 的 `remote_entry_run_build()` 中做一次判断即可。

### D2: push 行为

HARBOR_HOST 为空时，即使 `PUSH=true` 也不执行 push（无目标可推）。逻辑：push 条件从 `PUSH == true` 改为 `PUSH == true && HARBOR_HOST 非空`。

### D3: build.sh 校验放松

移除 HARBOR_HOST 的必填校验。HARBOR_PROJECT 同样改为可选（跟随 HARBOR_HOST）。

## Risks / Trade-offs

**[Risk] 有 Harbor 环境误删 HARBOR_HOST** → `PUSH=true` 但 HARBOR_HOST 为空时 push 会被静默跳过。可接受：构建成功，只是没推。日志会显示实际 tag，用户可发现。
