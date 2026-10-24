# Tasks

## 1. 生成

- [x] 1.1 新增 TSVBuilder，验证表头、空值、制表符、换行、引号
- [x] 1.2 GridDataSource 提供选中行 TSV，验证列顺序
- [x] 1.3 自定义 GridTableView 实现 copy:，验证 Command+C 写入剪贴板

## 2. 设置

- [x] 2.1 复制时读取 copyIncludesHeader，验证开关生效

## 3. 验证

- [x] 3.1 测试程序覆盖 TSVBuilder 五种情况
- [x] 3.2 运行 openspec validate --strict add-copy-tsv，验证无报错
