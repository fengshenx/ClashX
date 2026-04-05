# Menu 菜单重构评估

本文档用于说明菜单性能问题的根因、当前代码已经落地的优化，以及后续仍值得做的改进。

## 背景

历史上的主要卡顿场景是：

- 顶层菜单里有十几个 proxy group
- 每个 group 下有几十个 proxy
- 鼠标从 group A 滑到 group B 时，B 的子菜单在 `menuNeedsUpdate` 里同步创建大量 `ProxyMenuItem`

当 `ProxyMenuItem` 使用 `ProxyItemView` 渲染时，创建成本不低：

- 创建 `ProxyItemView` / `effectView`
- 创建并布局 `nameLabel` / `delayLabel`
- 查询 `ProxyDelayCache`
- 注册 highlight delegate
- 选中项额外创建 `NSImageView`

这些工作都发生在用户 hover 子菜单的热路径上，直接造成明显卡顿。

## 当前实现状态

### 1. 方案 A 已经落地：Eager Populate

当前代码已经不再依赖“首次打开子菜单时再 populate”的旧逻辑。

在 [`MenuItemFactory.swift`](/Users/mxwu/Documents/code/ClashX/ClashX/General/Managers/MenuItemFactory.swift#L190) 中，`generateSelectorMenuItem`、`generateUrlTestFallBackMenuItem`、`generateLoadBalanceMenuItem`、`generateListOnlyMenuItem` 在创建 submenu 时会直接调用 `populate...`，并立即将 `submenu.isPopulated = true`。

因此，[`ProxyGroupMenu.menuNeedsUpdate()`](/Users/mxwu/Documents/code/ClashX/ClashX/Views/ProxyGroupMenu.swift#L68) 在正常路径下只会执行轻量刷新：

- 如果 `isPopulated == true`，调用 `refreshItemsFromCache()`
- 仅更新 selection 和 delay
- 不再为 select / loadBalance 子菜单批量创建 `ProxyItemView`

这已经把“首次 hover 某个 submenu 时的同步批量建 view”从交互热路径上移走了。

### 2. 当前仍保留轻量刷新路径

[`ProxyGroupMenu.refreshItemsFromCache()`](/Users/mxwu/Documents/code/ClashX/ClashX/Views/ProxyGroupMenu.swift#L50) 通过以下条件避免重复刷新：

- `ProxyDelayCache.shared.generation`
- 当前 group 的 `now`

只有这两个值变化时，才遍历已有 `ProxyMenuItem` 并调用 `refreshFromCache(group:)`。

这条路径的复杂度和风险都明显低于重新构建整个 submenu。

### 3. 方案 B 目前没有在仓库里实现

目前代码库里没有看到以下对象池实现：

- `ProxyItemViewPool`
- `dequeue` / `recycle`
- `ProxyItemView.configure(proxy:)`

所以“view 复用池”目前仍然只是备选思路，不应写成现状。

## 当前数据流

当前菜单刷新流程如下：

```text
AppDelegate.menuNeedsUpdate()
        │
        ▼
MenuItemFactory.refreshExistingMenuItems()
        │
        ├─ 先用 cachedMenuItems 立即刷新当前菜单
        │
        └─ 再异步请求 ApiRequest.getMergedProxyData()
              │
              ├─ 更新 ProxyDelayCache
              ├─ hash 不变：仅发送 .proxyBatchUpdate
              └─ hash 变化：refreshMenuItems() 重建菜单树
```

相关代码位置：

- [`AppDelegate.swift`](/Users/mxwu/Documents/code/ClashX/ClashX/AppDelegate.swift#L895)
- [`MenuItemFactory.refreshExistingMenuItems()`](/Users/mxwu/Documents/code/ClashX/ClashX/General/Managers/MenuItemFactory.swift#L54)
- [`ApiRequest.getMergedProxyData()`](/Users/mxwu/Documents/code/ClashX/ClashX/General/ApiRequest.swift#L221)

## 这次重构实际解决了什么

已经解决的问题：

- 消除了“用户第一次滑到某个 group 时，子菜单现场批量创建 view”的卡顿
- 打开已构建 submenu 时，通常只需做轻量 selection / delay 刷新
- `actionSelectProxy` 保留 optimistic update，菜单状态能更快反映选择结果

没有完全解决的问题：

- 菜单树重建仍然发生在主线程
- 顶层菜单每次打开仍会触发一次异步数据同步
- 当 proxy 列表结构真的变化时，`refreshMenuItems()` 仍可能比较重

## 当前方案的两个主要风险

### 1. “异步”不等于“不阻塞 UI”

[`ApiRequest.getMergedProxyData()`](/Users/mxwu/Documents/code/ClashX/ClashX/General/ApiRequest.swift#L229) 最终通过 `group.notify(queue: .main)` 回到主线程。

这意味着：

- 网络请求本身是异步的
- 但 `refreshMenuItems()` 里的菜单树重建工作仍在主线程执行

所以当前优化是把卡顿从“hover submenu 时”转移到了“菜单打开后数据刷新时的重建路径”，而不是彻底移出 UI 线程。

### 2. 当前 hash 判定过于粗糙

[`computeProxyDataHash()`](/Users/mxwu/Documents/code/ClashX/ClashX/General/Managers/MenuItemFactory.swift#L45) 目前只基于 `Set(info.proxiesMap.keys)` 计算。

这只能发现“proxy 名字集合变化”，发现不了这些变化：

- 某个 group 的 `all` 内容变化，但名字集合没变
- 某个 group 的成员顺序变化
- provider 合并后的结构变化，但 key 集合没变
- group 类型或关联关系变化，但 key 集合没变

在这些情况下，当前逻辑可能只发送 `.proxyBatchUpdate`，却没有真正重建 submenu，导致菜单内容陈旧。

## 后续建议

### 优先做：修正重建判定

下一步最值得做的不是对象池，而是让“何时必须重建菜单树”的判断更准确。

建议至少把以下内容纳入 hash / diff：

- `proxyGroups` 的顺序
- 每个 group 的 `type`
- 每个 group 的 `all`
- 每个 group 的 `now`

如果不想一开始就做复杂 diff，也可以先生成一个稳定的结构签名字符串，再 hash。

### 已落地：大组降级纯文本渲染

当前代码已经对大 group 启用降级策略：

- 小 group 继续使用 `ProxyItemView`
- 大 group 改用 `NSAttributedString`

当前阈值定义在 [`MenuItemFactory.swift`](/Users/mxwu/Documents/code/ClashX/ClashX/General/Managers/MenuItemFactory.swift) 中：

- `proxyItemViewThreshold = 20`
- `group.all?.count <= 20` 时仍使用 `ProxyItemView`
- 超过阈值时，select / loadBalance 菜单项自动退回纯文本渲染

这样能明显降低大菜单的建 view 成本，且实现复杂度远低于对象池。

### 仍应谨慎：View 复用池

`NSMenuItem.view` 在 AppKit 下的生命周期、highlight、selected、submenu 关系都比较脆弱。

对象池理论上能减少 view 分配，但会引入更多状态管理问题：

- 复用前必须彻底清理旧状态
- 需要保证 `enclosingMenuItem` 相关行为正确
- highlight delegate、selected 图标、delay 文本都要完整重置

在当前代码规模和缺少测试的前提下，这个方向不应作为第一优先级。

## 不建议做的事

- 不建议引入新的全局 Coordinator，仅为了管理 menu populate 生命周期
- 不建议把菜单刷新改造成重度 push/relay 模型
- 不建议为了“彻底消灭重建”而提前做复杂对象池

当前菜单结构本身并不复杂，主要问题仍然是重建时机和重建判定，而不是状态管理层次不够多。

## 验证方式

1. 十几个 proxy group、每组 40+ proxy，快速在 group 间移动鼠标，确认 submenu 打开无明显卡顿。
2. 切换 proxy 后关闭再打开菜单，确认 group header 和 submenu 选中状态一致。
3. 跑 Benchmark，确认 delay 数值能通过缓存刷新及时更新。
4. 调整配置让某个 group 的成员增删或排序变化，确认菜单会真正重建，而不是只更新 header。
5. 用 Instruments 的 Time Profiler 对比 `menuNeedsUpdate` 和 `refreshMenuItems()` 的耗时。
