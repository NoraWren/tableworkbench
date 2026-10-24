# Spec Delta

## Purpose

描述文本文件如何生成 Parquet 缓存、如何命中与失效，以及容量如何管理。

## ADDED Requirements

### Requirement: 首次打开后台生成缓存

打开 CSV 或 TSV 后，应用 SHALL 在后台把数据转成 Parquet，写入缓存目录。转换 SHALL NOT 阻塞当前表格的显示。

#### Scenario: 首次打开
- **WHEN** 用户首次打开一个 500MB CSV
- **THEN** 界面在 3 秒内可用，后台随后生成缓存文件

#### Scenario: 转换失败
- **WHEN** 后台转换因为磁盘或权限失败
- **THEN** 当前表格继续可用，不弹出阻塞错误，缓存保持缺失

### Requirement: 二次打开优先缓存

缓存存在且有效时，应用 SHALL 直接读取 Parquet，SHALL NOT 重新解析 CSV。行列内容和筛选排序结果 SHALL 与首次一致。

#### Scenario: 二次打开
- **WHEN** 用户再次打开同一个未修改的 CSV
- **THEN** 从缓存读取，打开时间不超过 1.5 秒，行数和列名不变

#### Scenario: 缓存被删
- **WHEN** 用户手动删除缓存文件后再打开
- **THEN** 回退到 CSV 路径，重新生成缓存，不报错

### Requirement: 缓存失效

缓存键 SHALL 包含文件绝对路径、大小、修改时间和格式版本。任一变化时 SHALL 视为新文件，不得读取旧缓存。

#### Scenario: 文件被修改
- **WHEN** 用户在两次打开之间修改了 CSV 内容
- **THEN** 使用新的缓存键，重新解析，不返回旧数据

#### Scenario: 写入中断
- **WHEN** 转换过程中应用退出
- **THEN** 不会留下被当作有效缓存的半截文件

### Requirement: 缓存容量

缓存总量 SHALL 有上限，默认 10GB。超出时按最后访问时间删除最旧的文件。

#### Scenario: 超过上限
- **WHEN** 缓存总量超过 10GB
- **THEN** 删除最旧的文件直到低于上限，当前文件不受影响
