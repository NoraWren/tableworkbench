# Proposal

## Why

R-SHELL-02 要求应用有完整的菜单和快捷键。现在命令只挂在工具栏按钮上，菜单栏里没有「文件」和「查询」，用户找不到打开、导出、运行这些动作，也没法用键盘发现它们。

## What Changes

- 增加命令总线，界面把动作和可用状态填进去，菜单只读状态。
- 文件菜单：打开文件（Command+O）、导出（Shift+Command+E）、关闭文件（Shift+Command+W）。
- 查询菜单：运行（Command+R）、取消（Command+.，v0.1 置灰）、新建查询（Command+N）。
- 视图菜单：侧栏（Control+Command+S）、检查器（Command+Option+I）、SQL 抽屉（Command+J）。
- 侧栏折叠状态写进 UserDefaults，重启后恢复。

## 需求

- R-SHELL-02：菜单与快捷键。
- R-SHELL-01：侧栏折叠状态恢复。

## 不做什么

- 不做深色模式菜单，外观跟随系统。
- 不做帮助菜单的外部链接，发布后再补。
- 「关闭文件」用 Shift+Command+W，把 Command+W 留给系统关窗口。需求原文写的是 Command+W，这里改快捷键是为了不破坏关闭窗口的肌肉记忆。

## 性能与只读

菜单只调用现有动作，不新增查询路径，只读约束不变。
