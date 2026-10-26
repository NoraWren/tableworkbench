# Tasks

## 1. 实现

- [x] 1.1 `TextFileTranscoder` 改成分块读写，验证 155 MB GBK 文件能转完
- [x] 1.2 增加 `textSafeCut`，优先按换行切，验证跨块内容一致
- [x] 1.3 增加 `gb18030SafePrefixLength` 按字节规则扫描，验证半字符回退
- [x] 1.4 增加 `wideSafeCut` 与 `utf16SafePrefixLength`，验证 UTF-16 跨块
- [x] 1.5 UTF-8 BOM 走 `copySkippingBOM` 流式去头，验证输出无 BOM

## 2. 验证

- [x] 2.1 `TableWorkbenchTests` 增加 GBK 与 UTF-16 大文件往返断言，`swift run TableWorkbenchTests` 全部通过
- [x] 2.2 用 `/usr/bin/time -l` 实测峰值 RSS：155 MB GBK 文件 601 MB → 224 MB
- [x] 2.3 转码耗时实测 2.2 秒 → 3.0 秒，记录在 `docs/bench-history.md`
- [x] 2.4 `openspec validate --strict add-streaming-transcode` 通过

