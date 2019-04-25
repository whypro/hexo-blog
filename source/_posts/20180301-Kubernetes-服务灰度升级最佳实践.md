---
title: Kubernetes 服务灰度升级最佳实践
tags:
  - 原创
  - Kubernetes
  - K8S
originContent: ''
categories: []
toc: true
date: 2018-03-01 18:10:00
---

本文主要介绍了 Deployment 和 StatefulSet 的升级机制和扩缩容机制，以及一些常用的配置项。并分别介绍了以这两种方式部署 Pod 时的对服务进行升级（包括滚动发布、蓝绿发布、灰度／金丝雀发布）的最佳实践。

## Deployment

### 升级机制

#### Rollout

Deployment 的 rollout 在 .spec.template 被修改时触发（比如镜像地址更新、Pod label 更新等等），其他修改（.spec.replicas 更新）不会触发。

更新时，k8s 通过计算 pod-template-hash，创建新的 ReplicaSet，由新的 rs 启动新的 Pod，不断替换旧 rs 的 Pod。

通过命令

```
kubectl -n <namespace> rollout status deployment/<deployment-name>
```

查看 Deployment rollout 的状态。

`.spec.strategy` 定义了更新 Pod 的策略：

``` yaml
minReadySeconds: 5
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1
    maxUnavailable: 1
```

- `spec.strategy.type` 可以为 Recreate 或 RollingUpdate。Recreate 先删掉旧 Pod 再创建新 Pod，RollingUpdate 则按照滚动升级的策略来更新。
- `maxUnavailable`：更新时，Deployment 确保不超过 25%（默认值） 的 Pod 处于 unavailable 状态。既可以是数量也可以是百分比，当 `maxSurge` 为 `0` 时 `maxUnavailable` 不能为 `0`。
- `maxSurge`：更新时，Deployment 确保当前实际创建的 Pod 数（包括新旧实例总和）不超过期望 Pod 数的 25%（默认值）。既可以是数量也可以是百分比。
- `minReadySeconds`：新创建的 Pod 变为 Ready 状态的最少时间，如果容器在该时间内没有 crash，则认为该 Pod 是 available 的。默认值为 0，表示一旦 readiness probe 通过后就变为 Ready，这时如果没有配置 `readinessProbe`，则只要 Pod 创建后就会为 Ready 状态，可能会导致服务不可用。

#### Rollover

当 Deployment 在 rollout 过程中被更新时，Deployment 会立即执行新的更新，停止之前的 rollout 动作，并根据期望实例数删除（缩容）之前的 Pod，这个过程叫做 rollover。

#### Rollback

获取 Deployment 的 rollout 历史，最新的 revision 即当前版本

```
kubectl -n <namespace> rollout history deployment/<deployment-name>
```

查看指定 revision 的详细信息

```
kubectl -n <namespace> rollout history deployment/<deployment-name> --revision=<revision_num>
```

回滚到上一个版本

```
kubectl -n <namespace> rollout undo deployment/<deployment-name>
```

回滚到指定版本

```
kubectl -n <namespace> rollout undo deployment/<deployment-name> --to-revision=<revision_num>
```

当 Deployment 回滚成功时，会生成 DeploymentRollback 事件

可以通过 `.spec.revisionHistoryLimit` 配置最多保留的 revision 历史个数（不包括当前版本），默认值为 2，即保留 3 个 revision。

#### Pause/Resume

当 Deployment 的 `.spec.paused = true` 时，任何更新都不会被触发 rollout。通过如下命令设置 Deployment 为 paused：

```
kubectl -n <namespace> rollout pause deployment/<deployment-name>
```

还原：

```
kubectl -n <namespace> rollout resume deploy/<deployment-name>
```

### 扩缩容机制

#### 手动扩缩容

可以通过修改 `.spec.replicas`，或者执行 kubectl 命令的方式对 Deployment 进行扩缩容：

```
kubectl scale deployment nginx-deployment --replicas=10
```

#### 自动扩缩容

k8s 支持通过创建 HorizontalPodAutoscaler，根据 CPU 利用率或者服务提供的 metrics，对 Deployment、Replication Controller 或者 ReplicaSet 进行自动扩缩容。

```
kubectl autoscale deployment nginx-deployment --min=10 --max=15 --cpu-percent=80
```

详细请参考：

[https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)

[https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/)

### 发布最佳实践

#### 滚动发布

滚动发布是 Deployment 默认支持的更新方式，除了上文介绍的 rollingUpdate 相关配置外，不需要其他特殊的配置工作，

#### 灰度／金丝雀发布

金丝雀发布通过同时创建两个 Deployments 来实现，通过 track 标签区分两个版本，稳定版本的 Deployment 定义如下：

``` yaml
    name: frontend
    replicas: 3
    ...
    labels:
       app: guestbook
       tier: frontend
       track: stable
    ...
    image: gb-frontend:v3
金丝雀版本的定义如下：
    name: frontend-canary
    replicas: 1
    ...
    labels:
       app: guestbook
       tier: frontend
       track: canary
    ...
    image: gb-frontend:v4
```

再配置 service 的 labelSelector 将流量同时导入两个版本的 Pod

``` yaml
  selector:
    app: guestbook
    tier: frontend
```

通过 `.spec.replicas` 数量和扩缩容机制可以灵活配置稳定版本和金丝雀版本的比例（上面的例子为 3:1），流量会按照这个比例转发至不同版本，一旦线上测试无误后，将 track = stable 的 Deployment 更新为新版本镜像，再删除 track = canary 的 Deployment 即可。

#### 蓝绿发布

与金丝雀发布类似，同时创建 2 个label 不同的 Deployment，例如，deployment-1 定义如下：

``` yaml
    name: frontend
    replicas: 3
    ...
    labels:
       app: guestbook
       tier: frontend
       version: v3
    ...
    image: gb-frontend:v3
deployment-2 定义如下：
    name: frontend
    replicas: 3
    ...
    labels:
       app: guestbook
       tier: frontend
       version: v4
    ...
    image: gb-frontend:v4
```

金丝雀发布通过修改 Deployment 的 replicas 数量和 Pod 镜像地址实现流量切换，而蓝绿发布通过修改 Service 的 labelSelector 实现流量切换。

原 service 定义如下：

``` yaml
  selector:
    app: guestbook
    tier: frontend
    version: v3
```

切量时修改为：

``` yaml
  selector:
    app: guestbook
    tier: frontend
    version: v4
```

## StatefulSet

StatefulSet 相对于 Deployment，具有以下特点：

- 稳定：唯一的 Pod 名称，唯一的网络ID，持久化存储
- 有序：部署和伸缩都按照顺序执行，滚动升级按照顺序执行

### 升级机制

- `.spec.updateStrategy` 定义了升级 StatefulSet 的 Pod 的行为
- `.spec.updateStrategy.type` 为 OnDelete （默认行为）时，用户手动删除 Pod 后，新的 Pod 才会创建；为 RollingUpdate 时，k8s 按照 {N-1 .. 0} 的顺序滚动更新每个 Pod。
- `.spec.updateStrategy.rollingUpdate.partition` 可以实现灰度发布，当 StatefulSet 更新时，所有序号大于或等于 partition 的 Pod 会滚动更新；所有序号小于 partition 的 Pod 不会更新，即使被删掉，也会创建旧版本的 Pod。当 partition 大于 replicas 时，任何 Pod 都不会被更新。

配置示例如下：

``` yaml
spec:
  replicas: 10
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      partition: 7  # 7, 8, 9 will be rolling updated
```

StatefulSet 也支持 `kubectl rollout` 命令，使用方法同 Deployment。

### 扩缩容机制

可以通过 `spec.podManagementPolicy` 来配置 StatefulSet 的扩缩容策略

``` yaml
spec:
  podManagementPolicy: OrderdReady
```

#### OrderedReady

默认行为

扩容时，Pod 按照 {0 .. N-1} 依次创建，并且前一个 Running／Ready 之后，后一个才会创建

缩容时，Pod 按照 {N-1 .. 0} 依次删除，前一个完全删除之后，后一个才会开始删除

#### Parallel

扩缩容时忽略顺序，并发创建或删除

注意，该配置仅仅对扩缩容（修改 replicas）的情况有效，升级 StatefulSet 时 k8s 依然按照次序来更新 Pod。

### 唯一网络 ID

每个 Pod 都有唯一的 hostname，格式为 <statefulset-name>-<Pod 序号>，domain name 的格式为 <headless-svc-name>.<namespace>.svc.cluster.local，通过该 domain name 可以解析到 StatefulSet 下所有的 Pod。通过  <statefulset-name>-<Pod 序号>.<headless-svc-name>.<namespace>.svc.cluster.local 可以解析到指定 Pod。

### 稳定存储

通过配置 StatefulSet 的 `volumeClaimTemplates`，k8s 会为每个 Pod 创建 PV 和 PVC 并绑定。当 Pod 删除时，对应的 PVC 不会被删除，当重新创建时，仍然会绑定到之前的 PV。

``` yaml
  volumeClaimTemplates:
  - metadata:
      name: www
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: "my-storage-class"
      resources:
        requests:
          storage: 1Gi
```

### 发布最佳实践

#### 滚动发布

滚动发布需要配置 `.spec.updateStrategy.type` 为 `RollingUpdate`，StatefulSet 的默认行为是按照 {N-1 .. 0} 的顺序依次更新。

``` yaml
spec:
  updateStrategy:
    type: RollingUpdate
```

#### 蓝绿发布

蓝绿发布与 Deployment 的方式相同，通过创建 2 个 StatefulSet，修改 Service 的方式实现切量。

#### 灰度／金丝雀发布

金丝雀发布通过修改 StatefulSet 的 `.spec.updateStrategy.rollingUpdate.partition` 的值来实现发布。

例如 replicas 为 10 时，Pod 的序号为 0 - 9，首先将 partition 设置为 7，再修改 StatefulSet 的 Pod template 配置，会依次触发 Pod 9, 8, 7 的滚动更新，Pod 0-6 依然维持老版本，此时老版本与旧版本的比例为 7:3。线上验证无误后，再将 partition 设置为 0，依次触发 Pod 6 - 0 的滚动更新，此时全部更新至新版本。

``` yaml
spec:
  replicas: 10
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      partition: 7  # 7, 8, 9 will be rolling updated
```

## Replication Controller （官方已不推荐使用）

kubectl rolling-update 只适用于 Replication Controllers，已经被 Deployment 取代，在此不过多介绍。

[https://kubernetes.io/docs/tasks/run-application/rolling-update-replication-controller/](https://kubernetes.io/docs/tasks/run-application/rolling-update-replication-controller/)

## 参考

- Deployment：[https://kubernetes.io/docs/concepts/workloads/controllers/deployment/](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- Deployment Rolling Update：[https://tachingchen.com/blog/kubernetes-rolling-update-with-deployment/](https://tachingchen.com/blog/kubernetes-rolling-update-with-deployment/)
- 金丝雀部署：[https://kubernetes.io/docs/concepts/cluster-administration/manage-deployment/#canary-deployments](https://kubernetes.io/docs/concepts/cluster-administration/manage-deployment/#canary-deployments)
- 微服务部署：蓝绿部署、滚动部署、灰度发布、金丝雀发布：[https://www.jianshu.com/p/022685baba7d](https://www.jianshu.com/p/022685baba7d)
- StatefulSet：[https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/
](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/
)