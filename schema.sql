CREATE TABLE notes (
  id          TEXT PRIMARY KEY,                  -- filename stem
  title       TEXT NOT NULL,                     -- required; a note without title is skipped
  keywords    TEXT,                              -- raw space-separated string, e.g. 'odin memory-management'
  collections TEXT,                              -- raw space-separated string, e.g. "hub odin"
  excerpt     TEXT,                              -- display only, helps LLM select notes to read among search results
  out_degree  INTEGER NOT NULL DEFAULT 0          -- distinct outbound targets; precomputed at finalize
);

-- nodes are 'note' entries
CREATE TABLE edges (
  source_id TEXT NOT NULL,
  target_id TEXT NOT NULL,
  PRIMARY KEY (source_id, target_id)
) WITHOUT ROWID;

-- efficient backlinks querying support
CREATE INDEX idx_edges_target ON edges(target_id);

-- We want to emphasize results from relevant collection(s), hence query with
--
-- bm25(1.0, 1.0, 10.0)
--
-- ... to prioritize matches in `collections` 10x, ensuring notes
-- in relevant collection(s) generally win out over notes which
-- otherwise match many of the other keywords.
--
-- To populate this table (after populating `notes`), run:
-- INSERT INTO notes_fts(notes_fts) VALUES('rebuild');
CREATE VIRTUAL TABLE notes_fts USING fts5(
  title,
  keywords,
  collections,
  content='notes',
  content_rowid='rowid',
  tokenize='porter unicode61 remove_diacritics 1'
);
