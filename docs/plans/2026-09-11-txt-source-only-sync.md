# TXT 源文件唯一云端存储实施计划

> 状态：进行中（开发分支：`fix/txt-source-only-sync`）
> 开发基线：云端 `release` / `main` / `anx-ai-v1.1.0`，commit `6e4825284b9a9beccce576a6108f7dc891b70a62`
> 发布流程：`release -> 开发分支 -> 合并 release 测试 -> 发版 -> main 同步`
> 审计日期：2026-09-12
> 验收前提：用户已清理旧书籍和旧数据，仅保留原始 TXT/EPUB/其他格式文件；新版将从干净数据库重新导入和同步。旧记录仍保留安全回退，但不作为本次主流程验收前提。

## 1. 目标

保留 TXT 原始文件作为唯一云端书籍源，在每台设备本地按当前章节识别规则生成可丢弃的 EPUB 阅读缓存；同时移除书籍正式文件名后的时间戳，冲突时使用 `(1)`、`(2)` 命名。

原始输入文件和本地阅读缓存必须有明确边界：

- TXT 原文保存到应用书库的 `file/` 目录，并参与 WebDAV 同步。
- TXT 转换生成的 EPUB 只保存到应用缓存目录，不进入 WebDAV 书籍文件清单。
- 数据库保存源文件路径、源格式、源 MD5、本地缓存路径和缓存指纹。
- 打开或下载 TXT 时，如果缓存缺失、损坏、源内容变化、章节规则变化或解析器版本变化，则懒重建缓存。
- 现有云端旧 EPUB 在本阶段不自动删除。

## 2. 范围和非目标

### 范围

- TXT 导入和替换
- TXT -> EPUB 本地缓存生命周期
- WebDAV 源文件同步、下载和释放本地空间
- 数据库迁移
- 稳定文件名和冲突命名
- TXT 阅读位置兼容
- 旧数据分类审计
- 相关测试和开发文档

### 非目标

- 本阶段不重写 TXT 原生阅读器。
- 不改变现有章节识别规则算法。
- 不移除临时转换工作目录中用于并发隔离的随机目录标识。
- 不自动删除用户已有本地文件或历史远端 EPUB。
- 不把旧版只有 EPUB 的记录猜测成 TXT 源。

## 3. 云端 release 基线审计

云端实际分支状态：

- `release`：`6e4825284b9a9beccce576a6108f7dc891b70a62`
- `main`：`6e4825284b9a9beccce576a6108f7dc891b70a62`
- `master`：不存在
- `release` 与 `main` 当前 0 ahead / 0 behind，并与 tag `anx-ai-v1.1.0` 对齐

release 已经包含的前置修复：

- TXT 输入文件不再被无条件删除，导入清理开始区分输入所有权。
- TXT 段落边界和标题/Toc 处理有所修复。
- EPUB 临时构建目录支持并发隔离。
- `file_md5` 与 `source_md5` 已分离，数据库版本已经到 v8。

release 尚未完成的目标：

| 目标 | 基线事实 | 本分支状态 |
|---|---|---|
| TXT 是正式 `file/` 源文件 | 原流程把 TXT 转成永久 `file/*.epub` | 已接入 source-only 导入 |
| EPUB 仅本地缓存 | 原 EPUB 是数据库正式 `file_path` | 已接入 `cache/txt_epub/` |
| source/cache 字段 | 只有 `source_md5`/`file_md5` | 已新增完整兼容字段 |
| 缓存 fingerprint | 未实现 | 已新增纯契约和 sidecar marker |
| UTF-16 源位置 | 只保存 EPUB CFI | 已实现百分比 -> UTF-16 offset 过渡闭环；完整 CFI -> 原文映射仍待后续 |
| 正式命名 | `标题-毫秒时间戳.ext` | TXT 已改为标题和 `(n)` 冲突命名；非 TXT 保持旧语义 |
| WebDAV 源文件唯一同步 | 按 `Book.filePath` 同步永久 EPUB | 已改为 TXT 源路径；非 TXT 保持旧语义 |
| 历史远端 EPUB | 原同步清理可能误删未入库文件 | 本分支禁止自动删除远端 `file/*.epub` |
| 完整旧库迁移 | 仅有 source_md5 v8 迁移 | 已新增 source/cache/offset 字段 v9 迁移和兼容读取 |

## 4. 当前实现设计

### 4.1 数据模型

`tb_books` 新增可空字段：

```text
source_file_path       TEXT
source_format          TEXT
source_md5             TEXT
cache_file_path        TEXT
cache_fingerprint      TEXT
source_text_offset     INTEGER
source_text_length     INTEGER
position_context       TEXT
```

旧 `file_path`、`file_md5`、`last_read_position` 继续保留：

- TXT 新记录中 `file_path` 和 `source_file_path` 指向正式 TXT。
- TXT 的 `cache_file_path` 是 `txt_epub/<fingerprint>/generated.epub` 相对缓存标识。
- 非 TXT 新记录的 `source_file_path` 回退为 `file_path`，`cache_file_path` 为空。
- legacy 记录不根据文件名推断 TXT 来源。

### 4.2 缓存

缓存位于应用缓存目录：

```text
应用缓存目录/
└─ txt_epub/
   └─ <fingerprint>/
      ├─ generated.epub
      └─ generated.fingerprint
```

缓存指纹至少由以下内容稳定计算：

- 原始 TXT MD5
- 当前章节规则的稳定序列化
- TXT 解析器版本

转换在临时文件完成后再替换目标缓存；转换失败时保留旧缓存。

### 4.3 TXT 进度

当前已实现的是安全的过渡方案：

- 保留 `last_read_position` 作为当前缓存 EPUB 的 CFI 兼容值。
- 使用缓存 EPUB 上报的百分比乘以规范化 TXT 的 UTF-16 code-unit 长度，得到 `source_text_offset`。
- 用 offset 附近上下文生成 `position_context`，用于检测源文本漂移。
- `reading_percentage` 对 TXT 按 offset/source length 计算。
- 每次打开 TXT 都重新校验源 MD5；如果源内容变化，在尚无精确迁移器时清空旧 CFI/上下文并安全回到 0%，不静默跳到错误章节。

限制必须明确：当前还没有完整的 EPUB CFI 到原始 TXT 字符位置映射器。因此百分比映射可在规则变化后保持大致位置，但不是精确段落锚点。后续若需要严格恢复，应在转换器中输出源 offset 元数据，并让 foliate 事件携带源锚点。

### 4.4 文件命名

TXT 正式文件名：

```text
书名.txt
书名 (1).txt
书名 (2).txt
```

正式文件名不使用时间戳或 UUID。临时 EPUB 构建仍可以使用随机隔离目录，随机标识不能进入正式书名。

### 4.5 WebDAV

- TXT 的 canonical sync path 优先使用 `source_file_path`。
- TXT 缓存不进入上传清单、下载清单或远端文件清理比较。
- TXT 释放本地空间前先上传源 TXT；上传失败不删除本地源。
- TXT 释放成功后删除本地源 TXT 和安全解析出的本地缓存。
- 历史远端 `file/*.epub` 本阶段保留，不自动删除。
- legacy 只有 EPUB 的记录继续按旧 `file_path` 兼容，不猜测其 TXT 源。

## 5. 已完成实现

- [x] 从云端 release 同步并创建 `fix/txt-source-only-sync`。
- [x] 新增 `BookSource`、缓存指纹和 `TxtPosition` 纯数据契约。
- [x] Book 模型增加 source/cache/offset 字段及兼容序列化。
- [x] 数据库升级到 v9，新增字段按列幂等迁移。
- [x] 新增纯文件名分配器。
- [x] TXT 导入保存正式 TXT，生成 EPUB 进入应用缓存。
- [x] TXT 替换保持正式源文件语义。
- [x] 阅读入口在打开前检查并懒重建 TXT 缓存。
- [x] TXT 进度增加 UTF-16 offset 的安全过渡保存。
- [x] WebDAV 同步使用 TXT canonical source path。
- [x] 远端历史 EPUB 禁止自动孤儿清理。
- [x] 释放 TXT 时上传失败保护本地源文件。
- [x] 修复 `releaseBook` 使用 `TxtCacheManager.resolveBookCacheFile` 解析本地缓存文件，杜绝 `getBasePath` 误将缓存相对路径当作文档库路径解析的风险。
- [x] 强化 `TxtCacheManager.ensureCache` 的原子性保障：写入 marker 失败或替换失败时自动回滚恢复旧缓存与旧 marker，且清理临时文件。
- [x] 修复缓存安全校验的正则转义、路径穿越、缓存目录残留和长 TXT 进度保存的重复全量读取问题。
- [ ] 完整 CFI -> TXT 原文 offset 映射。
- [ ] 书签、笔记、搜索结果全部迁移到可跨缓存的源锚点。
- [ ] 真实 SQLite v8 -> v9 fixture 升级测试。
- [ ] Flutter/真实 WebView 端到端测试。

## 6. 测试要求

聚焦测试：

```bash
flutter test test/models/book_source_test.dart \
  test/service/txt_cache/txt_cache_key_test.dart \
  test/service/txt_cache/txt_position_test.dart \
  test/service/book_filename_allocator_test.dart \
  test/service/txt_cache/txt_cache_manager_test.dart \
  test/service/txt_import_replace_semantics_test.dart \
  test/service/txt_cache_rebuild_test.dart \
  test/page/txt_reading_entry_test.dart \
  test/providers/sync_source_file_only_test.dart \
  test/providers/sync_rebuild_txt_cache_test.dart \
  test/service/txt_cache/legacy_book_migrator_test.dart
```

最终检查：

```bash
flutter test
flutter analyze
git diff --check
git diff --name-only
```

当前开发环境尚未发现 `flutter`/`dart` CLI，因此不能声称本地 Flutter 测试通过；必须在 CI 或安装 SDK 的环境中执行并记录真实结果。

## 7. 安全和兼容边界

- 不使用宽泛目录删除。
- 不删除用户外部输入，除非调用者明确标记其拥有临时文件。
- 不把 TXT 缓存写入 `file/` 或上传到 `anx/data/file/`。
- 不把缓存路径通过 `getBasePath()` 当成文档库路径解析。
- 不自动删除历史远端 EPUB。
- 不根据 legacy EPUB 文件名猜测 TXT 源。
- 不把随机临时构建标识用作正式书籍名。
- 非 TXT EPUB/PDF/MOBI 继续使用现有正式文件和同步语义。

## 8. 后续发布流程

1. 在 `fix/txt-source-only-sync` 完成实现和测试。
2. 提交开发分支并创建合并请求到 `release`。
3. 在 `release` 上进行 Android/iOS/Windows/macOS 的导入、打开、阅读、同步和释放验收。
4. 测试通过后打发行版本。
5. 发布成功后将 `release` 合并/同步到 `main`。
6. 历史远端 EPUB 清理另立任务，展示具体路径、大小和数量后再由用户确认。
