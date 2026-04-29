---
name: zotero-research
description: Use when the user wants to search, browse, read, summarize, cite, annotate, or manage their Zotero library through Zotero MCP. Triggers include Zotero, 文献库, 查文献, 读论文, PDF 注释, citation key, BibTeX, 标签, 集合, and adding or updating Zotero items.
metadata:
  short-description: Search and manage Zotero via MCP
---

# Zotero Research

Use this skill when working with the user's Zotero library through the `zotero` MCP server.

## Defaults

- Use local Zotero first. If a database path is needed, read it from `ZOTERO_DB_PATH`; do not assume a hard-coded machine path.
- Semantic search uses the default local embedding model from `zotero-mcp` (`all-MiniLM-L6-v2`), not Ollama, OpenAI, or Gemini.
- Prefer read-only exploration unless the user explicitly asks to add, update, tag, create collections, or merge items.
- Write operations are allowed when requested clearly. For destructive or hard-to-reverse operations, especially duplicate merging, show a dry-run/preview first.

## Installed Zotero Add-ons

- The user's Zotero desktop has `llm-for-zotero` installed: https://github.com/yilewang/llm-for-zotero.
- Treat `llm-for-zotero` as a Zotero-side PDF reader and library assistant, separate from the Codex `zotero` MCP server.
- Do not assume Codex can operate the add-on UI directly through MCP. Use Zotero MCP for library search, metadata, full text, notes, annotations, tags, and collections.
- If the user refers to the Zotero LLM plugin or Zotero AI assistant, map that to `llm-for-zotero`. Use its outputs only when they are saved into Zotero notes/annotations, file-based notes, or pasted by the user.

## MinerU Markdown Cache

- `llm-for-zotero` can parse PDFs with MinerU and save enhanced Markdown plus extracted images in Zotero's data directory.
- Do not assume the cache is in the Obsidian notes folder. The configured Obsidian folder may be empty even when MinerU output exists.
- Resolve Zotero's actual data directory first:
  - Inspect Zotero `prefs.js` under the active profile, usually `%APPDATA%\Zotero\Zotero\Profiles\*\prefs.js`.
  - If `extensions.zotero.useDataDir` is `true`, use `extensions.zotero.dataDir`.
  - Otherwise fall back to Zotero's default data directory.
- MinerU cache layout:
  - `<Zotero data directory>\llm-for-zotero-mineru\<numeric item or attachment id>\full.md`
  - `<Zotero data directory>\llm-for-zotero-mineru\<numeric item or attachment id>\manifest.json`
  - `<Zotero data directory>\llm-for-zotero-mineru\<numeric item or attachment id>\images\`
- Prefer `full.md` for paper-content questions when it exists; it is usually richer than generic PDF text extraction and keeps figure/table references.
- Use `manifest.json`, the first Markdown heading, or Zotero MCP metadata to map numeric cache folders back to human-readable paper titles.
- Legacy cache names may exist as `_content.md` inside the numeric folder or `<id>.md` directly under the MinerU cache directory, but `full.md` is the current primary file.
- Current machine snapshot from 2026-04-23: 57 `full.md` files were found under the MinerU cache. Treat this as a stale-prone snapshot and verify live before reporting counts.

## Search Flow

1. Start broad with recent items, collections, tags, or keyword search:
   - `zotero_get_recent`
   - `zotero_get_collections`
   - `zotero_get_tags`
   - `zotero_search_items`
   - `zotero_advanced_search`
2. Use `zotero_semantic_search` for concept-level questions, literature discovery, or when the user's query is a topic rather than an exact title/author.
3. After identifying candidates, read details with:
   - `zotero_get_item_metadata`
   - `zotero_get_item_fulltext`
   - `zotero_get_item_children`
   - `zotero_get_annotations`
   - `zotero_get_notes`
4. When the user references a citation key, use `zotero_search_by_citation_key` before fuzzy search.

## Answering Style

- Answer in Chinese unless the user asks otherwise.
- Cite the Zotero item key, title, authors, and year/date when reporting findings.
- Distinguish metadata, full text, notes, and annotations when conclusions depend on them.
- If full text or annotations are unavailable, say that clearly and fall back to metadata/abstract.
- For multi-paper comparisons, keep a compact table first, then a short synthesis.

## Write Operations

Allowed when the user clearly requests them:

- Add items: `zotero_add_by_doi`, `zotero_add_by_url`, `zotero_add_from_file`
- Organize items: `zotero_create_collection`, `zotero_manage_collections`, `zotero_batch_update_tags`
- Edit metadata: `zotero_update_item`
- Duplicates: run `zotero_find_duplicates` first; only call `zotero_merge_duplicates` after the user confirms the preview.

## Maintenance

- If semantic search returns no results, check `zotero_get_search_database_status` and consider `zotero_update_search_database`.
- If local connection fails, ask the user to open Zotero and enable local API communication in Zotero preferences.
- If search quality is weak, rebuild the semantic database with full-text indexing before changing embedding providers.
