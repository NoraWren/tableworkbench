# Design

## 卡片为什么不该无限长

错误卡片挂在 `ContentView` 的 `.overlay(alignment: .bottom)` 上，内容是 `ImportErrorCard`。展开技术细节时卡片按内容增高，而底层容器没有高度上限，卡片的下半截会画到窗口底边以下，被窗口裁掉——展开的内容看不见，用户的操作等于没反应。

## 做法

1. 技术细节文本包进 `ScrollView`，`.frame(maxHeight: 120)`。DuckDB 的原始报错经常十几行，120pt 大约能看六行，再多就滚。
2. 卡片整体 `.frame(maxHeight: 320)`，`overlay` 上再给 `.padding(.bottom, 8)`，保证贴着底边也不越界。
3. 文字仍是等宽、`.textSelection(.enabled)`，能选中复制。

## 否决的方案

- 改成弹窗：打断用户当前的分析，一个提示不值得。
- 展开后自动滚到可见位置：治不了根，窗口再矮一点照样被裁。
- 省略号截断原始报错：R-IMP-07 要的就是能看到原始报错。

