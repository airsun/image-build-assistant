# 部署规约

全局默认规则。AI 生成 k8s YAML 时以此为基础，项目 deploy note 中描述的内容覆盖对应默认值。

## 网络访问

- 所有 web 服务默认通过 Ingress 暴露
- 域名由 `projects.yaml` 的 `deploy.domain` 字段指定
- 内部创建 ClusterIP Service，Ingress 指向该 Service
- 不使用 NodePort、LoadBalancer

## 工作负载

- 默认 Deployment 类型，replicas: 1
- resource requests: cpu 100m, memory 256Mi
- resource limits: cpu 500m, memory 512Mi
- 项目有特殊需求在 deploy note 中说明

## 镜像拉取

- 地址格式：`{HARBOR_HOST}/{harbor_project}/{image_name}:{version}`
- imagePullSecrets 由集群全局配置，YAML 中不需要声明

## Namespace

- 项目指定的 namespace 如不存在，生成 namespace.yaml
- 不做 ResourceQuota 等高级配置，由集群管理员另行管理

## 存储

- 默认无持久化
- 需要 PVC 时在 deploy note 中说明容量和挂载路径
- 使用集群默认 StorageClass，不指定

## 配置注入

- 默认无额外配置
- 需要 ConfigMap 时在 deploy note 中说明 key 和用途
- 需要 Secret 时只生成骨架（data 字段为占位符），部署人员手动填写实际值
- Secret 的占位符格式：`<BASE64_ENCODED_VALUE>` 并在 deploy-note.md 中列出需填写的 key
