# 本地表格工作台（暂名）

拖进一个 500MB 的 CSV，两秒打开，一千多万行也能滚动，数据不出本机。

<!-- TODO: 第一屏 GIF，8 秒内，拖入到出数据 -->

## 三个数字

| 场景 | 实测 |
|---|---|
| 500MB CSV 冷打开 | 2.0 秒 |
| 同一个文件二次打开（缓存） | 0.59 秒 |
| 1000 万行第 100 块 | 0.12 秒 |

测试机器：MacBook Pro 18,3（M1 Pro），16GB，macOS 27.0.1，release 构建。

## 支持

- 打开 CSV、TSV、Parquet、xlsx
- 按列排序，条件筛选，AND/OR 组合
- SQL 抽屉，只读查询
- 拖拽字段生成透视表
- 列检查器：空值、去重、范围、均值、中位数、直方图
- 导出 CSV / Parquet，Command+C 复制选区为 TSV
- xlsx 多工作表选择

## 不做什么

不做单元格编辑，不做公式，不做图表，不做协作，不做云同步。它是分析器，不是表格编辑器。

## 构建

需要 macOS 14+ 和 Swift 6。

    cd app
    swift build
    swift run TableWorkbench

测试：

    cd app
    swift run TableWorkbenchTests

开发用 .app：

    ./scripts/make-app-bundle.sh
    open build/TableWorkbench.app

打包 dmg：

    ./scripts/make-dmg.sh

签名需要 Apple Developer 账号和 Developer ID Application 证书，设置 SIGN_IDENTITY 后脚本会用正式证书重签。

## 已知限制

- xlsx 的公式只读缓存值，缓存值缺失时留空。
- Excel 的日期样式暂按单元格原始值输出，ISO 字符串会正常识别。
- 透视的空组合显示 NULL，不强制补零。
- 导出暂不做进度条和取消。
- 没有签名和公证的包会被 Gatekeeper 拦截。

## 许可证

待定，见 docs/requirements/12-decisions-risks.md 的 R-DEC-07。
