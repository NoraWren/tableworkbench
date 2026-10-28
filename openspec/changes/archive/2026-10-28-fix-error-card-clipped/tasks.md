# Tasks

## 1. 修

- [x] 1.1 ImportErrorCard 的技术细节改成整行按钮展开；短报错按内容高度显示，超过 8 行才限高 120pt 滚动
- [x] 1.2 卡片底部留 8pt，展开后不越出窗口（外层没加 maxHeight：加了会把卡片撑到 320pt 高，短报错留一大块空白）

## 2. 验证

- [x] 2.1 swift build 通过，无新增警告（只剩原有的 DeprecatedDeclaration 与两条 ld search path）
- [x] 2.2 release 包真机：PNG 改名成 .csv 打开，点「查看技术细节」这几个字（不是小箭头）即可展开，报错完整可见（docs/media/verification/import-error-detail.png）
- [x] 2.3 多行报错（parquet 损坏）按内容高度显示不撑高，坏 parquet 的 connectionQueryError 两行直接展开
- [x] 2.4 TableWorkbenchTests 全绿

## 3. 文档

- [x] 3.1 docs/requirements/02-data-import.md 的 R-IMP-07 勾掉三条验收并写证据
- [x] 3.2 openspec validate --strict fix-error-card-clipped 通过

