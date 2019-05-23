---
title: Kubernetes 容器生命周期管理
tags:
  - 原创
  - Kubernetes
  - K8S
  - 云计算
categories: []
toc: true
date: 2018-04-04 16:09:40
---

## 健康检查和就绪检查

### 健康检查（Liveness Probe）

如果设置了 `livenessProbe`，k8s (kubelet) 会每隔 n 秒执行预先配置的行为来检查容器是否健康

当健康检查失败时，k8s 会认为容器已经挂掉，会根据 `restartPolicy` 来对容器进行重启或其他操作。

每次检查有 3 种结果，`Success`、`Failure`、`Unknown`

如果不配置，默认的检查状态为 `Success`

<!-- more -->

**什么时候不需要健康检查**：如果服务在异常后会自动退出或 crash，就不必配置健康检查，k8s 会按照重启策略来自动操作。

**什么时候需要健康检查**：相反，如果服务异常必须由 k8s 主动介入来重启容器，就需要配置健康检查

### 就绪检查（Readiness Probe）

如果设置了 `readinessProbe`，k8s (kubelet) 会每隔 n 秒检查容器对外提供的服务是否正常

当就绪检查失败时，k8s 会将 Pod 标记为 `Unready`，将 Pod IP 从 endpoints 中剔除，即不会让之后的流量通过 service 发送过来。

在首次检查之前，初始状态为 `Failure`

如果不配置，默认的状态为 `Success`

**什么时候需要就绪检查**：如果在服务启动后、初始化完成之前不想让流量过来，就需要配置就绪检查。

**什么时候不需要就绪检查**：除了上述场景，在 Pod 被删除时，k8s 会主动将 Pod 置为 `UnReady` 状态，之后的流量也不会过来，因此针对这种情况不必配置就绪检查。

### 参数

健康／就绪检查支持以下参数：

- `initialDelaySeconds`: 容器启动后，进行首次检查的等待时间（秒）
- `periodSeconds`: 每次检查的间隔时间（秒）
- `timeoutSeconds`: 执行检查的超时时间（秒），默认值为 1，最小值是 1
- `successThreshold`: 检查失败时，连续成功 n 次后，认为该容器的健康／就绪检查成功。默认值为 1，最小值是 1，对于健康检查必须为 1
- `failureThreshold`: 连续失败 n 次后，认为该容器的健康／就绪检查失败。默认值为 3，最小值是 1

### 检查方式

#### Exec 方式

```
    livenessProbe:
      exec:
        command:
        - cat
        - /tmp/healthy
```

#### HTTP GET 请求方式

```
    livenessProbe:
      httpGet:
        path: /healthz
        port: 8080
        httpHeaders:
        - name: X-Custom-Header
          value: Awesome
```

支持的参数包括：

- `host`: 目标主机地址，默认值为 pod IP
- `scheme`: HTTP 或 HTTPS，默认为 HTTP
- `path`: 访问路径
- `httpHeaders`: 自定义请求头
- `port`: 目标端口号，有效值 1~65535

#### TCP Socket 方式

```
    livenessProbe:
      tcpSocket:
        port: 8080
```

支持的参数包括：

- `host`: 目标主机地址，默认值为 pod IP
- `port`: 目标端口号，有效值 1~65535

## 容器重启策略

`restartPolicy` 是 livenessProbe `Failure` 后执行的策略，作用于 Pod 的每个容器，可以配置为 `Always`、`OnFaiiure`、`Never`，默认值为 `Always`。 

`restartPolicy` 只会影响本机节点重启容器的策略，并不会影响 Pod 重新调度的行为，重启的方式按照时间间隔（10s, 20s, 40s, ..., 5min）来重启容器，并且每 10min 重置间隔时间

重启策略 `restartPolicy` 的配置通过以下几个场景来举例说明：

1. Pod Running 状态，包含 1 个容器，容器正常退出

记录 completion 事件

- `Always`: 重启容器，Pod phase 保持 `Running` 状态
- `OnFaiiure`: 不重启容器，Pod phase 变为 `Succeeded`
- `Never`: 不重启容器，Pod phase 变为 `Succeeded`

2. Pod Running 状态，包含 1 个容器，容器异常退出

记录 failure 事件

- `Always`: 重启容器，Pod phase 保持 `Running` 状态
- `OnFaiiure`: 重启容器，Pod phase 保持 `Running` 状态
- `Never`: 不重启容器，Pod phase 变为 `Failed`

3. Pod Running 状态，包含 2 个容器，其中一个容器异常退出

记录 failure 事件

- `Always`: 重启容器，Pod phase 保持 `Running` 状态
- `OnFaiiure`: 重启容器，Pod phase 保持 `Running` 状态
- `Never`: 不重启容器，Pod phase 保持 `Running` 状态

此时如果第二个容器退出（无论正常还是异常）

记录 failure 事件

- `Always`: 重启容器，Pod phase 保持 `Running` 状态
- `OnFaiiure`: 重启容器，Pod phase 保持 `Running` 状态
- `Never`: 不重启容器，Pod phase 变为 `Failed`

4. Pod Running 状态，包含 1 个容器，容器被 OOM (out of memory) killed

记录 OOM 事件

- `Always`: 重启容器，Pod phase 保持 `Running` 状态
- `OnFaiiure`: 重启容器，Pod phase 保持 `Running` 状态
- `Never`: 不重启容器，Pod phase 变为 `Failed`

5. Pod Running 状态，遇到节点异常（比如磁盘挂掉、segmented out）

根据异常原因记录相应事件

无论设置为哪种策略，Pod 状态变为 `Failed`，并尝试在其他节点重新创建（如果 Pod 是通过 Controller 管理的）

## 容器生存周期事件处理

k8s 在容器创建或终止时会发送 `postStart` 或 `preStop` 事件，用户可以通过配置 handler，对这两个容器事件进行处理。

k8s 在容器创建之后发送 `postStart` 事件，postStart handler 是异步执行，所以并不保证会在容器的 entrypoint 之前执行，不过容器代码会阻塞住直到 postStart handler 执行完成。执行成功后，容器状态才会设为 `Running`

k8s 在容器 terminate 之前发送 `preStop` 事件，terminate 行为会阻塞，直到 preStop handler 同步执行成功或者 Pod 配置的 grace period 超时 (`terminationGracePeriodSeconds`)。注意：如果不是主动终止，k8s 不会发送 `preStop` 事件（比如正常退出）。

如果 postStart 或 preStop handler 执行失败，k8s 直接 kill 掉容器。

### handler 执行方式

#### Exec 方式

```
    lifecycle:
      postStart:
        exec:
          command: ["/bin/sh", "-c", "echo Hello from the postStart handler > /usr/share/message"]
```

#### HTTP GET 方式

```
    lifecycle:
      postStart:
        httpGet:
          path: /healthz
          port: 8080
          httpHeaders:
          - name: X-Custom-Header
            value: Awesome
```

## 配置示例

livenessProbe 和 readinessProbe 的配置项完全相同，只是检查失败后的行为不同

lifecycle 的 exec 和 httpGet 和 livenessProbe 对应的配置项相同。

```
apiVersion: v1
kind: Pod
metadata:
  name: example
spec:
  containers:
  - name: example
    // ... 
    livenessProbe:
      exec:
        command:
        - cat
        - /tmp/healthy
      initialDelaySeconds: 5
      periodSeconds: 10
    readinessProbe:
      tcpSocket:
        port: 8080
      initialDelaySeconds: 10
      periodSeconds: 10
    lifecycle:
      postStart:
        exec:
          command: ["/bin/sh", "-c", "echo Hello from the postStart handler > /usr/share/message"]
      preStop:
        httpGet:
          host: xxx.xxx.xxx
          path: /stop
          port: 8080
  restartPolicy: OnFailure
```

## 参考

Pod 生命周期：https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/

健康检查和就绪检查：https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-probes/

容器生存周期事件处理：
https://kubernetes.io/docs/tasks/configure-pod-container/attach-handler-lifecycle-event/  
https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/