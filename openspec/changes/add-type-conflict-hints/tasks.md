# Tasks

## 1. 统计

- [x] 1.1 ColumnStats 增加 numericCount 与 nonNumericExamples，验证默认值
- [x] 1.2 文本列计算 numericCount，验证混合列 3/4
- [x] 1.3 取最多两个反例，验证横线案例
- [x] 1.4 纯文本与数值列不提示，验证条件

## 2. 界面

- [x] 2.1 检查器显示类型冲突区块，验证数字、反例
- [x] 2.2 纯文本与数值列不显示，验证不误报

## 3. 验证

- [x] 3.1 测试程序覆盖混合、纯文本、数值三种列
- [x] 3.2 运行 openspec validate --strict add-type-conflict-hints，验证无报错
