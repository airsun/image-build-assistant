## ADDED Requirements

### Requirement: 全局部署规约文档

系统 SHALL 维护 `image-builder/deploy-conventions.md` 文件，定义所有 k8s 部署项目的默认行为。AI 生成 YAML 时 MUST 以此文档为基础，项目 deploy note 中描述的内容覆盖规约默认值。

规约文档 SHALL 覆盖以下方面：

**网络访问**：默认通过 Ingress + 域名暴露，内部创建 ClusterIP Service，不使用 NodePort / LoadBalancer

**工作负载**：默认 Deployment 类型，replicas 1，默认 resource requests/limits 有合理预设值

**镜像拉取**：地址格式为 `{HARBOR_HOST}/{harbor_project}/{image_name}:{version}`，imagePullSecrets 由集群全局配置

**Namespace**：不存在则生成创建用的 YAML

**存储**：默认无持久化，需要时由 deploy note 说明，使用集群默认 StorageClass

**配置注入**：默认无额外配置，需要 ConfigMap/Secret 时由 deploy note 说明，Secret 只生成骨架不含实际值

#### Scenario: AI 生成时应用规约默认值

- **WHEN** AI 为一个项目生成 k8s YAML，且 deploy note 未提及某方面配置
- **THEN** AI SHALL 使用 deploy-conventions.md 中定义的默认值

#### Scenario: deploy note 覆盖规约

- **WHEN** deploy note 中明确描述了与规约不同的需求（如"内存 limits 2Gi"）
- **THEN** AI SHALL 以 deploy note 为准，覆盖规约默认值

#### Scenario: 规约文档更新

- **WHEN** 运维人员发现规约与集群实际配置不一致
- **THEN** 运维人员 SHALL 更新 deploy-conventions.md，后续生成的 YAML 自动采用新规约

### Requirement: 规约作为双重受众文档

deploy-conventions.md SHALL 同时服务于两类读者：AI（作为 YAML 生成的参考规则）和人（理解默认行为、知道何时需要在 deploy note 中声明例外）。文档 MUST 以清晰的条目化中文书写。

#### Scenario: 运维人员查阅规约了解默认行为

- **WHEN** 运维人员需要了解 "不写 deploy note 时系统默认会怎么部署"
- **THEN** deploy-conventions.md SHALL 提供明确答案
