---
title: Kubelet PLEG 源码解析
tags:
  - 原创
  - Kubernetes
  - K8S
  - 云计算
  - Kubelet
categories: []
toc: true
date: 2019-06-04 12:48:26
---

PLEG (pod lifecycle event generator) 是 kubelet 中一个非常重要的模块，它主要完成以下几个目标：

1. 从 runtime 中获取 pod 当前状态，产生 pod lifecycle events
2. 从 runtime 中获取 pod 当前状态，更新 kubelet pod cache

本文我们通过分析 PLEG 模块的源码，来加深对 Kubernetes 的理解，也可以加速在使用过程对一些疑难问题的排查和处理，同时后期可以对一些问题源码进行优化，来解决一些 Kubernetes 本身的坑。

<!-- more -->

## PLEG 初始化

PLEG 模块在 kubelet 实例创建时初始化，在 `pkg/kubelet/kubelet.go` 文件中：

``` golang
func NewMainKubelet(...) (*Kubelet, error) {
    // ...
    klet.pleg = pleg.NewGenericPLEG(klet.containerRuntime, plegChannelCapacity, plegRelistPeriod, klet.podCache, clock.RealClock{})
    // ...
}
```

我们简单看看 `NewGenericPLEG` 的实现，见 `pkg/kubelet/pleg/generic.go`：

``` golang
// NewGenericPLEG instantiates a new GenericPLEG object and return it.
func NewGenericPLEG(runtime kubecontainer.Runtime, channelCapacity int,
    relistPeriod time.Duration, cache kubecontainer.Cache, clock clock.Clock) PodLifecycleEventGenerator {
    return &GenericPLEG{
        relistPeriod: relistPeriod,
        runtime:      runtime,
        eventChannel: make(chan *PodLifecycleEvent, channelCapacity),
        podRecords:   make(podRecords),
        cache:        cache,
        clock:        clock,
    }
}
```

`NewGenericPLEG` 函数有几个重要的参数：

- `runtime`

    实参为 `klet.containerRuntime`，负责容器运行时的管理，对 pod 或 container 状态的获取、同步和删除都通过 `runtime` 来操作。

- `channelCapacity`

    实参为 `plegChannelCapacity`，是 `eventChannel` 有缓冲 channel 的大小，默认值 `1000`，也就是单节点最大支持 1000 个 pod lifecycle event 同时触发。

- `relistPeriod`

    实参为 `plegRelistPeriod`，是 PLEG 检测的周期，默认值 `1s`。

- `cache`

    实参为 `klet.podCache`，保存着所有 pod 状态的缓存，kubelet 通过 container runtime 更新 pod 缓存。


`plegChannelCapacity` 和 `plegRelistPeriod` 这两个常量的定义在 `pkg/kubelet/kubelet.go` 文件里：

``` golang
const (
    plegChannelCapacity = 1000

    plegRelistPeriod = time.Second * 1
)
```


## PLEG 接口定义

`NewGenericPLEG` 返回的类型 `*GenericPLEG` 实现了 `PodLifecycleEventGenerator` 接口，我们暂且忽略 `GenericPLEG` 结构体的具体实现，先分析一下 `PodLifecycleEventGenerator` 接口，这个接口在 `pkg/kubelet/pleg/pleg.go` 文件中定义，包含三个方法：

``` golang
// PodLifecycleEventGenerator contains functions for generating pod life cycle events.
type PodLifecycleEventGenerator interface {
    Start()
    Watch() chan *PodLifecycleEvent
    Healthy() (bool, error)
}
```

- `Start` 启动 PLEG。
- `Watch` 返回一个 channel，pod lifecycle events 会发送到这个 channel 里，kubelet 通过这个 channel 来获取事件，执行处理动作。
- `Healty` 返回 PLEG 的健康状态。kubelet 通过这个函数判断 PLEG 是否健康。

我们再看看 pod lifecycle event 的定义，见 `pkg/kubelet/pleg/pleg.go` 文件：


``` golang
// PodLifeCycleEventType define the event type of pod life cycle events.
type PodLifeCycleEventType string

const (
    // ContainerStarted - event type when the new state of container is running.
    ContainerStarted PodLifeCycleEventType = "ContainerStarted"
    // ContainerDied - event type when the new state of container is exited.
    ContainerDied PodLifeCycleEventType = "ContainerDied"
    // ContainerRemoved - event type when the old state of container is exited.
    ContainerRemoved PodLifeCycleEventType = "ContainerRemoved"
    // PodSync is used to trigger syncing of a pod when the observed change of
    // the state of the pod cannot be captured by any single event above.
    PodSync PodLifeCycleEventType = "PodSync"
    // ContainerChanged - event type when the new state of container is unknown.
    ContainerChanged PodLifeCycleEventType = "ContainerChanged"
)

// PodLifecycleEvent is an event that reflects the change of the pod state.
type PodLifecycleEvent struct {
    // The pod ID.
    ID types.UID
    // The type of the event.
    Type PodLifeCycleEventType
    // The accompanied data which varies based on the event type.
    //   - ContainerStarted/ContainerStopped: the container name (string).
    //   - All other event types: unused.
    Data interface{}
}
```

`PodLifecycleEvent` 结构保存着以下信息：

- `ID`: pod ID

- `Type`: 事件类型

    `PodLifecycleEventType` 有以下几种：

    - `ContainerStarted`: 容器状态变为 `Running`
    - `ContainerDied`: 容器状态变为 `Exited`
    - `ContainerRemoved`: 容器消失
    - `PodSync`: PLEG 中未使用
    - `ContainerChanged`: 容器状态变为 `Unknown`

- `Data`: 容器 ID（源码注释是 container name，应该是错误）

## PLEG 接口调用

下面我们看看 kubelet 是在哪里使用 `PodLifecycleEventGenerator` 接口里的三个方法的。

### 启动

kubelet 在 `Run` 函数中执行 `Start`，启动 PLEG。

``` golang
// Run starts the kubelet reacting to config updates
func (kl *Kubelet) Run(updates <-chan kubetypes.PodUpdate) {
    // ...

    // Start the pod lifecycle event generator.
    kl.pleg.Start()
    kl.syncLoop(updates, kl)
}
```

### 事件处理

最后在 `syncLoop` 中执行 `Watch`，获取到这个关键的 channel `plegCh`，然后在 `syncLoopIteration` 函数中从 channel 中获取事件，进行处理。

``` golang
// syncLoop is the main loop for processing changes. It watches for changes from
// three channels (file, apiserver, and http) and creates a union of them. For
// any new change seen, will run a sync against desired state and running state. If
// no changes are seen to the configuration, will synchronize the last known desired
// state every sync-frequency seconds. Never returns.
func (kl *Kubelet) syncLoop(updates <-chan kubetypes.PodUpdate, handler SyncHandler) {
    klog.Info("Starting kubelet main sync loop.")
    // The syncTicker wakes up kubelet to checks if there are any pod workers
    // that need to be sync'd. A one-second period is sufficient because the
    // sync interval is defaulted to 10s.
    syncTicker := time.NewTicker(time.Second)
    defer syncTicker.Stop()
    housekeepingTicker := time.NewTicker(housekeepingPeriod)
    defer housekeepingTicker.Stop()
    plegCh := kl.pleg.Watch()
    // ...
    for {
        // ...
        if !kl.syncLoopIteration(updates, handler, syncTicker.C, housekeepingTicker.C, plegCh) {
            break
        }
        // ...
    }
}

```

`syncLoopIteration` 是 kubelet 事件处理的核心函数，它的职责是从多个不同类型的 channel 中获取事件，然后分发给不同的 handler 去处理。


``` golang
// syncLoopIteration reads from various channels and dispatches pods to the
// given handler.
func (kl *Kubelet) syncLoopIteration(configCh <-chan kubetypes.PodUpdate, handler SyncHandler,
    syncCh <-chan time.Time, housekeepingCh <-chan time.Time, plegCh <-chan *pleg.PodLifecycleEvent) bool {
    select {
    case u, open := <-configCh:
        // ...
    case e := <-plegCh:
        if isSyncPodWorthy(e) {
            // PLEG event for a pod; sync it.
            if pod, ok := kl.podManager.GetPodByUID(e.ID); ok {
                klog.V(2).Infof("SyncLoop (PLEG): %q, event: %#v", format.Pod(pod), e)
                handler.HandlePodSyncs([]*v1.Pod{pod})
            } else {
                // If the pod no longer exists, ignore the event.
                klog.V(4).Infof("SyncLoop (PLEG): ignore irrelevant event: %#v", e)
            }
        }

        if e.Type == pleg.ContainerDied {
            if containerID, ok := e.Data.(string); ok {
                kl.cleanUpContainersInPod(e.ID, containerID)
            }
        }
    case <-syncCh:
        // ...
    case update := <-kl.livenessManager.Updates():
        // ...
    case <-housekeepingCh:
        // ...
    }
    return true
}
```

- `configCh` 负责获取 pod 配置更新事件。
- `syncCh` 是一个定时器，定时获取 pod sync 事件，对需要的 pod 进行同步，默认是 `1s`。
- `housekeepingCh` 也是一个定时器，定时获取 pod Cleanup 事件，对需要的 pod 进行清理，默认值是 `2s` 
- `plegCh` 负责获取 pod lifecycle 事件
- `livenessManager.Updates` 负责获取 liveness probe 事件
- `handler` 是个事件处理接口 (`SyncHandler`)，获取到上面的时间后调用对应的事件处理方法，kubelet 主类本身默认实现了这个接口。


在这里我们只关心对 pod lifecycle 事件的处理：从代码上看，kubelet 收到 pod lifecycle 事件之后，首先判断事件类型是不是值得触发 pod 同步，如果是 `ContainerRemoved`，则忽略该事件。如果是其他事件，且 pod 信息还没有被删除，调用 `HandlePodSyncs` 产生 UpdatePod 事件，交给 kubelet pod Worker 进行异步更新。最后，如果是 `ContainerDied` 事件，为了防止退出容器堆积，会按照一定的策略移除已退出的容器。


### 健康检测

kubelet 对 PLEG 模块的健康检测，通过 runtimeState 来管理，kubelet 在初始化 PLEG 后通过 `addHealthCheck` 将 `klet.pleg.Healthy` 健康监测方法注册至 runtimeState，runtimeState 定时调用 `Healthy` 方法检查 PLEG 的健康状态。参见 `pkg/kubelet/kubelet.go`：

``` golang
func NewMainKubelet(...) (*Kubelet, error) {
    // ...
    klet.runtimeState.addHealthCheck("PLEG", klet.pleg.Healthy)
    // ...
}
```

`addHealthCheck` 实现在 `pkg/kubelet/runtime.go` 中：

``` golang
func (s *runtimeState) addHealthCheck(name string, f healthCheckFnType) {
    s.Lock()
    defer s.Unlock()
    s.healthChecks = append(s.healthChecks, &healthCheck{name: name, fn: f})
}
```

然后在 `syncLoop` 中定时执行 `runtimeErrors`，这里 `syncLoop` 采用了简单的 backoff 机制，如果 runtimeState 各个模块状态都正常，则每次循环默认 sleep `100ms`，如果出现异常状态，则 sleep duration * 2，最大变为 `5s`，参见 `pkg/kubelet/kubelet.go`：

``` golang
func (kl *Kubelet) syncLoop(updates <-chan kubetypes.PodUpdate, handler SyncHandler) {
    klog.Info("Starting kubelet main sync loop.")
    // ...
    const (
        base   = 100 * time.Millisecond
        max    = 5 * time.Second
        factor = 2
    )
    duration := base
    for {
        if err := kl.runtimeState.runtimeErrors(); err != nil {
            klog.Infof("skipping pod synchronization - %v", err)
            // exponential backoff
            time.Sleep(duration)
            duration = time.Duration(math.Min(float64(max), factor*float64(duration)))
            continue
        }
        // reset backoff if we have a success
        duration = base
        // ...
    }
}
```

`runtimeErrors` 实现在 `pkg/kubelet/runtime.go` 中：

``` golang 
func (s *runtimeState) runtimeErrors() error {
    s.RLock()
    defer s.RUnlock()
    errs := []error{}
    // ...
    for _, hc := range s.healthChecks {
        if ok, err := hc.fn(); !ok {
            errs = append(errs, fmt.Errorf("%s is not healthy: %v", hc.name, err))
        }
    }

    return utilerrors.NewAggregate(errs)
}
```

这里也是依次执行各个模块事先注册的 healthy check 函数，如果任何一个模块返回 false，则认为整个 runtimeState 的状态为 unhealthy。

## Generic PLEG 实现


我们再回到 `PodLifecycleEventGenerator` 接口的实现 —— `GenericPLEG` 的定义，见 `pkg/kubelet/pleg/generic.go` 文件：

``` golang
type GenericPLEG struct {
    // The period for relisting.
    relistPeriod time.Duration
    // The container runtime.
    runtime kubecontainer.Runtime
    // The channel from which the subscriber listens events.
    eventChannel chan *PodLifecycleEvent
    // The internal cache for pod/container information.
    podRecords podRecords
    // Time of the last relisting.
    relistTime atomic.Value
    // Cache for storing the runtime states required for syncing pods.
    cache kubecontainer.Cache
    // For testability.
    clock clock.Clock
    // Pods that failed to have their status retrieved during a relist. These pods will be
    // retried during the next relisting.
    podsToReinspect map[types.UID]*kubecontainer.Pod
}
```

- `relistPeriod` 是 PLEG 检测周期，默认为 `1s`
- `runtime` 是 container runtime，负责获取 pod 和 container 的状态信息
- `podRecords` 缓存 pod 以及 Container 的基本信息
- `cache` 缓存 pod 的运行时状态
- `eventChannel` 是 PLEG 通过对比 pod 缓存信息和当前信息，生成 pod lifecycle events 的 channel
- `relistTime` 是上一次执行完 PLEG 检测的时刻 
- `podsToReinspect` 保存 PLEG 检测失败的 Pod，以便下次再次检测
- `clock` 是一个时间管理对象，作用是获取当前时间

然后我们基于接口方法，来分析 `GenericPLEG` 的实现：

``` golang
// Start spawns a goroutine to relist periodically.
func (g *GenericPLEG) Start() {
    go wait.Until(g.relist, g.relistPeriod, wait.NeverStop)
}
```

`Start` 启动了一个 goroutine，以 `1s` 的间隔无限执行 `relist` 函数。这里要注意 `wait.Until` 的行为，如果 `relist` 执行时间大于 period 设置的值，则时间窗会滑动至 relist 执行完毕的那一时刻。也就是说如果 period 是 `1s`，relist 从第 `0s` 开始，花了 `10s`，结束时是第 `10s`，那么下一次 relist 会从第 `11s` 开始执行。

relist 函数的实现如下：

``` golang
// relist queries the container runtime for list of pods/containers, compare
// with the internal pods/containers, and generates events accordingly.
func (g *GenericPLEG) relist() {
    klog.V(5).Infof("GenericPLEG: Relisting")

    if lastRelistTime := g.getRelistTime(); !lastRelistTime.IsZero() {
        metrics.PLEGRelistInterval.Observe(metrics.SinceInSeconds(lastRelistTime))
        metrics.DeprecatedPLEGRelistInterval.Observe(metrics.SinceInMicroseconds(lastRelistTime))
    }

    timestamp := g.clock.Now()
    defer func() {
        metrics.PLEGRelistDuration.Observe(metrics.SinceInSeconds(timestamp))
        metrics.DeprecatedPLEGRelistLatency.Observe(metrics.SinceInMicroseconds(timestamp))
    }()

    // Get all the pods.
    podList, err := g.runtime.GetPods(true)
    if err != nil {
        klog.Errorf("GenericPLEG: Unable to retrieve pods: %v", err)
        return
    }

    g.updateRelistTime(timestamp)

    pods := kubecontainer.Pods(podList)
    g.podRecords.setCurrent(pods)

    // Compare the old and the current pods, and generate events.
    eventsByPodID := map[types.UID][]*PodLifecycleEvent{}
    for pid := range g.podRecords {
        oldPod := g.podRecords.getOld(pid)
        pod := g.podRecords.getCurrent(pid)
        // Get all containers in the old and the new pod.
        allContainers := getContainersFromPods(oldPod, pod)
        for _, container := range allContainers {
            events := computeEvents(oldPod, pod, &container.ID)
            for _, e := range events {
                updateEvents(eventsByPodID, e)
            }
        }
    }

    var needsReinspection map[types.UID]*kubecontainer.Pod
    if g.cacheEnabled() {
        needsReinspection = make(map[types.UID]*kubecontainer.Pod)
    }

    // If there are events associated with a pod, we should update the
    // podCache.
    for pid, events := range eventsByPodID {
        pod := g.podRecords.getCurrent(pid)
        if g.cacheEnabled() {
            // updateCache() will inspect the pod and update the cache. If an
            // error occurs during the inspection, we want PLEG to retry again
            // in the next relist. To achieve this, we do not update the
            // associated podRecord of the pod, so that the change will be
            // detect again in the next relist.
            // TODO: If many pods changed during the same relist period,
            // inspecting the pod and getting the PodStatus to update the cache
            // serially may take a while. We should be aware of this and
            // parallelize if needed.
            if err := g.updateCache(pod, pid); err != nil {
                // Rely on updateCache calling GetPodStatus to log the actual error.
                klog.V(4).Infof("PLEG: Ignoring events for pod %s/%s: %v", pod.Name, pod.Namespace, err)

                // make sure we try to reinspect the pod during the next relisting
                needsReinspection[pid] = pod

                continue
            } else if _, found := g.podsToReinspect[pid]; found {
                // this pod was in the list to reinspect and we did so because it had events, so remove it
                // from the list (we don't want the reinspection code below to inspect it a second time in
                // this relist execution)
                delete(g.podsToReinspect, pid)
            }
        }
        // Update the internal storage and send out the events.
        g.podRecords.update(pid)
        for i := range events {
            // Filter out events that are not reliable and no other components use yet.
            if events[i].Type == ContainerChanged {
                continue
            }
            select {
            case g.eventChannel <- events[i]:
            default:
                metrics.PLEGDiscardEvents.WithLabelValues().Inc()
                klog.Error("event channel is full, discard this relist() cycle event")
            }
        }
    }

    if g.cacheEnabled() {
        // reinspect any pods that failed inspection during the previous relist
        if len(g.podsToReinspect) > 0 {
            klog.V(5).Infof("GenericPLEG: Reinspecting pods that previously failed inspection")
            for pid, pod := range g.podsToReinspect {
                if err := g.updateCache(pod, pid); err != nil {
                    // Rely on updateCache calling GetPodStatus to log the actual error.
                    klog.V(5).Infof("PLEG: pod %s/%s failed reinspection: %v", pod.Name, pod.Namespace, err)
                    needsReinspection[pid] = pod
                }
            }
        }

        // Update the cache timestamp.  This needs to happen *after*
        // all pods have been properly updated in the cache.
        g.cache.UpdateTime(timestamp)
    }

    // make sure we retain the list of pods that need reinspecting the next time relist is called
    g.podsToReinspect = needsReinspection
}
```

relist 中 export 了两个监控指标：`relist_interval` 和 `relist_latency`，它们俩的关系是：

```
relist_interval = relist_latency + relist_period
```

整个 relist 的流程大致为：

1. 从 container runtime 获取所有 Pod，更新至 podRecords 的 current state
2. 遍历 podRecords，对比 current state 和 old state，产生 lifecycle events 并按照 pod 分组
3. 遍历 pod 和 对应的 events，从 container runtime 获取 pod status 更新 cache（记录失败的 Pod，准备下次重试），并将 PLEG event （除了 ContainerChanged 事件）放入 eventChannel
4. 遍历上次 relist 更新 cache 失败的 Pod，尝试再次获取 pod status 更新 cache

relist 函数通过访问 container runtime 将 pod 和 container 的实际状态更新至 kubelet 的 pod cache。其他模块 (pod worker) 使用的 pod cache，都由 PLEG 模块更新。

pod lifecycle event 的生成通过 `generateEvents` 函数比较 old state 和 new state 来实现：

``` golang
func generateEvents(podID types.UID, cid string, oldState, newState plegContainerState) []*PodLifecycleEvent {
	if newState == oldState {
		return nil
	}

	klog.V(4).Infof("GenericPLEG: %v/%v: %v -> %v", podID, cid, oldState, newState)
	switch newState {
	case plegContainerRunning:
		return []*PodLifecycleEvent{{ID: podID, Type: ContainerStarted, Data: cid}}
	case plegContainerExited:
		return []*PodLifecycleEvent{{ID: podID, Type: ContainerDied, Data: cid}}
	case plegContainerUnknown:
		return []*PodLifecycleEvent{{ID: podID, Type: ContainerChanged, Data: cid}}
	case plegContainerNonExistent:
		switch oldState {
		case plegContainerExited:
			// We already reported that the container died before.
			return []*PodLifecycleEvent{{ID: podID, Type: ContainerRemoved, Data: cid}}
		default:
			return []*PodLifecycleEvent{{ID: podID, Type: ContainerDied, Data: cid}, {ID: podID, Type: ContainerRemoved, Data: cid}}
		}
	default:
		panic(fmt.Sprintf("unrecognized container state: %v", newState))
	}
}
```

顺便看看 Container Runtime 接口，对于 Container Runtime，我们主要关注 PLEG 用到的两个方法 `GetPods` 和 `GetPodStatus`，参照 `pkg/kubelet/container/runtime.go` 文件：

``` golang
// Runtime interface defines the interfaces that should be implemented
// by a container runtime.
// Thread safety is required from implementations of this interface.
type Runtime interface {
    // ...
    // GetPods returns a list of containers grouped by pods. The boolean parameter
    // specifies whether the runtime returns all containers including those already
    // exited and dead containers (used for garbage collection).
    GetPods(all bool) ([]*Pod, error)
    // ...
    // GetPodStatus retrieves the status of the pod, including the
    // information of all containers in the pod that are visible in Runtime.
    GetPodStatus(uid types.UID, name, namespace string) (*PodStatus, error)
    // ...
}
```

`GetPods` 主要是获取 pod 列表和 pod/container 的基本信息，`GetPodStatus` 则获取单个 pod 内所有容器的详细状态信息（包括 pod IP 和 runtime 返回的一些状态）。


关于事件通知，上面提到 PLEG 会将 pod lifecycle events 放入一个 channel，`Watch` 方法返回了这个 channel。

``` golang
// Watch returns a channel from which the subscriber can receive PodLifecycleEvent
// events.
// TODO: support multiple subscribers.
func (g *GenericPLEG) Watch() chan *PodLifecycleEvent {
    return g.eventChannel
}
```

那么 PLEG 如何判断自己工作是否正常呢？通过暴露 `Healthy` 方法，`GenericPLEG` 保存了上一次开始执行 relist 的时间戳，`Healthy` 方法判断与当前时间的间隔，只要大于阈值，则认为 PLEG unhealthy。

``` golang
// Healthy check if PLEG work properly.
// relistThreshold is the maximum interval between two relist.
func (g *GenericPLEG) Healthy() (bool, error) {
    relistTime := g.getRelistTime()
    if relistTime.IsZero() {
        return false, fmt.Errorf("pleg has yet to be successful")
    }
    elapsed := g.clock.Since(relistTime)
    if elapsed > relistThreshold {
        return false, fmt.Errorf("pleg was last seen active %v ago; threshold is %v", elapsed, relistThreshold)
    }
    return true, nil
}
```

这个阈值在 `pkg/kubelet/pleg/generic.go` 中定义：

``` golang
const (
    // The threshold needs to be greater than the relisting period + the
    // relisting time, which can vary significantly. Set a conservative
    // threshold to avoid flipping between healthy and unhealthy.
    relistThreshold = 3 * time.Minute
)
```

默认是 `3m`，也就是说只要 relist 执行时间超过 3 分钟，则认为 PLEG unhealthy。

## 总结

最后我们总结一下整个流程：

1. kubelet 创建并启动 PLEG 模块，watch pod lifecycle event
2. PLEG 模块每隔 `1s` 执行 relist，relist 完成两个目标：
    1. 获取 pod list，对比 pod 的 old state 和 new state，产生 PLEG events
    2. 依次获取 pod status，并更新 pod cache
3. kubelet watch 到 pod lifecycle events，产生 update pod 事件通知 pod worker 执行 sync pod 操作
4. kubelet 持续检查 runtime state (PLEG) 的健康状态

本文对下面几个方面没有深入介绍，后面有空会写单独的文章将源码解析分享出来：

- kubelet sync loop iteration
- pod worker 的 sync pod 机制
- container runtime
- node status 节点状态控制