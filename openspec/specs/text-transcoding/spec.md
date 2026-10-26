# text-transcoding Specification

## Purpose
描述文本导入前把 GB18030、UTF-16、带 BOM 的 UTF-8 转成 UTF-8 临时文件时的行为与边界。

## Requirements

### Requirement: 分块转码不改内容

转码结果 SHALL 与整文件一次性转码的结果逐字节一致；多字节字符 SHALL NOT 被切成替换字符。

#### Scenario: GBK 大文件跨块
- **WHEN** 打开一个超过 4 MB、含 12 万行中文的 GB18030 CSV
- **THEN** 转码后的文本与原文本完全相等，首尾行和中段中文都不乱码

#### Scenario: UTF-16 大文件跨块
- **WHEN** 打开一个超过 4 MB 的 UTF-16LE CSV
- **THEN** 转码结果与原文本完全相等

### Requirement: 峰值内存与文件大小解耦

转码 SHALL 按块读取，内存里同时存在的数据量 SHALL 不超过一块加上一个完整字符的残留。

#### Scenario: 155 MB GBK 文件
- **WHEN** 转码 155 MB 的 GB18030 CSV
- **THEN** 进程峰值 RSS 不超过 300 MB（实测 224 MB）

### Requirement: BOM 处理

带 UTF-8 BOM 的文件 SHALL 去掉开头三字节 BOM，其余内容原样保留。

#### Scenario: 带 BOM 的小文件
- **WHEN** 打开以 EF BB BF 开头的 CSV
- **THEN** 输出首字节就是第一列的字符，没有多余 BOM 字节

### Requirement: 边界扫描

没有换行可切时，转码 SHALL 退回按字节宽度规则找最后一个完整字符；末尾只剩半个字符时 SHALL 把它留到下一块。

#### Scenario: 末尾半个 GB18030 字符
- **WHEN** 一段缓冲只剩 `0x41 0xBF`
- **THEN** 安全前缀长度为 1，`0xBF` 留给下一块

#### Scenario: 完整双字节字符
- **WHEN** 缓冲是 `0x41 0xBF 0xCD 0x42`
- **THEN** 安全前缀长度为 4，整段都被认作完整
