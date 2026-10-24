# Tasks

## 1. 实现

- [x] 1.1 新增 GridTextCellView，验证右对齐、置灰、截断与 tooltip
- [x] 1.2 GridDataSource 改用自绘单元格，验证 10 万行表滚动正常

## 2. 验证

- [x] 2.1 复测 20 / 100 / 200 列三种规模，三次都回到 16.7 毫秒预算内
- [x] 2.2 开发包里确认文字对齐、交替行背景、行号列与改前一致
- [x] 2.3 运行 openspec validate --strict draw-cells-directly
