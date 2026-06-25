# Examples

这个目录放公开、安全、可复制的示例内容，用来帮助新用户理解 A-Brain 的输入格式。

## Files

- `sample-source.md`: 可放入 `library/sources` 后运行 `ingest-library` 的 source 示例。
- `sample-note.md`: 可放入 `knowledge/notes` 后运行 `learn-candidate` 的 note 示例。

## Try

```powershell
Copy-Item .\examples\sample-source.md .\library\sources\sample-source.md
Copy-Item .\examples\sample-note.md .\knowledge\notes\sample-note.md
.\scripts\ingest-library.cmd -SourcePath .\library\sources\sample-source.md
.\scripts\learn-candidate.cmd -InputPath .\knowledge\notes\sample-note.md -InputType note
```
