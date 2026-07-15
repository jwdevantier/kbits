# kbits: Knowledge BITS

Small tool to index and search for relevant markdown notes.

## Quick start

```bash
kbits root                              # print default (platform-specific) notes directory path
kbits index                             # rebuild the search index
kbits read NOTE_ID                      # retrieve a note's contents
kbits search --limit 10 -p 1 QUERY...   # search notes (YAML output)
kbits help [SUBCOMMAND]                 # show usage info
```

## Notes format

Notes are markdown files with a fenced YAML front-matter. Required keys: `title`, `keywords`, `collections`. Recommended: `excerpt` (note summary).

```yaml
---
title: My Note
keywords: foo bar
collections: git work
excerpt: A short summary
---

Note content here...
```

**Important**: every entry in the front-matter must be an unquoted string as shown above.

## Note directory
- Notes live in a single directory
    - `kbits root` prints the default for your platform.
- All notes must live in the same flat directory, subdirectories are ignored
    - note IDs are derived from file's base name

## Indexing
**Important**: Run `kbits index` after adding/removing/changing notes to update the index.

- kbits metadata is stored in `<notes_dir>/_meta`
- `<notes_dir>/_meta/db/db.db` is the SQLite database storing notes metadata and a FTS5 full text search index
- `<notes_dir>/_meta/collections.yml`
    - Intended to be a single flat file of `key: DESC` entries. Used by pi extension when injecting a message into the system prompt encouraging the LLM to make use of the knowledge-base, and to be especially likely to use it if the topic discussed matches any of the collection keywords.

## Search results

- `./kbits search odin dynamic array append`
    - stems and tokenizes on word boundaries, do not write English phrases, write keywords
- Search implicitly OR's each given search term, the more terms match, the better the rank
- Ranks results using bm25
- Searches only in note's `title`, `keywords` and `collections` keys.
- Matches in `collections` are given much higher weight.
    - avoids your 'python' notes from cluttering results when searching for 'odin'
- Supports prefix searches, 'foo*' matches 'football', 'foosball', ...
- Supports suffix searches, '*tic' matches 'agentic', 'lunatic', ...

## LLM-friendly design

- CLI is self-describing (defaults to `help`, lists subcommands, `help SUBCOMMAND` describes usage)
- `read` returns one note per call
    - modern harnesses batch tool calls efficiently and it is easier for them to correlate requests to results this way than interpreting a custom multi-result tool response
- `search` returns a single fenced YAML block — simple, well-known format

## Tested models

- GLM 5.2 (large)
- Gemma 4 26B (small)
- Qwen 3.5 32B (small)

## Extension

A [pi.dev harness extension](https://github.com/jwdevantier/kbits.pi) is available.

## Building

```sh
# if you have nix, otherwise, install the odin compiler some other way
nix develop .#

# from the root directory
odin build . -out:kbits
```

