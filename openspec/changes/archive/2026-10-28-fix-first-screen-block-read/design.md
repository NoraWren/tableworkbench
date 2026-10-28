# Design

## 打点为什么放在应用里

录屏逐帧算只能拿到「两帧之间」的粒度，还要靠自动拖拽把文件送进去；拖拽失败时录到的是一段没加载的空白，容易把无效样本当成数字。改成应用内打点：拖放的松手时刻由 `FileDropContainerView.performDragOperation` 归零，后面每个阶段直接记相对秒数，脚本只负责拖，然后用打点文件判断这一轮是否有效。

线程边界：`OpenTiming` 用 `NSLock` 保护起点，导入在后台 `Task.detached` 里跑、打点从后台线程写，首帧打点在主线程。计时开关在进程启动时读一次环境变量，没设就整条路径不进。

## 取块为什么选 LIMIT/OFFSET

| 方案 | 第 1 块 | 第 100 块 | 第 200 块 | 结论 |
|---|---|---|---|---|
| `WHERE rowid >= a AND rowid < b ORDER BY rowid` | 0.40 s | 0.42 s | 0.42 s | 每块都全表扫，不能用 |
| `LIMIT 5000 OFFSET n` | 0.03 s | 0.09 s | 0.14 s | 采用 |
| 新增 `row_number() OVER () AS __rid` 再按 range 过滤 | 物化 1.6 → 5.2 s | — | — | 否决，物化代价吃不消 |

顺序怎么保证：物化表按插入序返回（DuckDB 默认 `preserve_insertion_order`），`__result` 的插入序就是排序后的顺序；Parquet 视图不物化，没有稳定的插入序，所以那条路继续按 `__rid` 过滤并显式 `ORDER BY`。

## NSTableView 为什么先按 0 行接

`tableView.dataSource = ...` 会让 AppKit 立刻按 `numberOfRows` 建内部行结构，326 万行花 0.57 秒；同样 326 万行在 `reloadData` 里只要 2 毫秒。所以 `makeNSView` 里先把协调者的 `rowCount` 临时置 0，接完 dataSource 再还原，真实行数由随后那次 `reloadData` 带进去。`updateNSView` 不需要这套，多打开或换视图时行数已经在结构里。

## 没采用的

- 延后后台转 Parquet：实测取块时间不变，不是它抢 CPU。
- 保留导入期 1.4 GB 内存上限不收回：取块时间不变，白白多占内存。
- 绕过 auto_detect 自己嗅探列类型：省不了多少，还可能把前导零的数字列导错。
