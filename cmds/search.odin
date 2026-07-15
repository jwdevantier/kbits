// SPDX-FileCopyrightText: 2026 Jesper Wendel Devantier
// SPDX-License-Identifier: BSD-2-Clause
package cmds
import "../sqlite"
import "core:c"
import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "core:strconv"
import "core:strings"

Search_Flags :: struct {
	limit: int,
	page:  int,
}

parse_search_flags :: proc(args: []string, opts: ^Search_Flags) -> (ndx: int, ok: bool) {
	i := 0
	for i < len(args) {
		arg := args[i]
		switch arg {
		case "-l", "--limit":
			if i + 1 >= len(args) {
				fmt.eprintfln("error: %s requires a value", arg)
				return i, false
			}
			val: int
			val, ok = strconv.parse_int(args[i + 1])
			if !ok {
				return i, false
			}
			opts.limit = val
			i += 2
		case "-p", "--page":
			if i + 1 >= len(args) {
				fmt.eprintfln("error: %s requires a value", arg)
				return i, false
			}
			val: int
			val, ok = strconv.parse_int(args[i + 1])
			if !ok {
				return i, false
			}
			opts.page = val
			i += 2
		case:
			return i, true
		}
	}
	return i, true
}

search :: proc(cfg: ^Config, args: []string) -> int {
	db_fpath: string
	err: os.Error
	db: sqlite.sqlite3
	stmt: sqlite.Stmt
	search_query: string

	@(static) query := `
		SELECT n.id, n.title, n.keywords, n.collections, n.excerpt
		FROM notes_fts
		JOIN notes AS n
		ON n.rowid = notes_fts.rowid
		WHERE notes_fts MATCH ?
		ORDER BY bm25(notes_fts, 1.0, 1.0, 10.0), n.rowid
		LIMIT ?
		OFFSET ?
	`

	opts: Search_Flags = Search_Flags {
		limit = 10,
		page  = 1,
	}

	ndx, ok := parse_search_flags(args, &opts)
	if !ok {
		return 1
	}
	offset := (opts.page - 1) * opts.limit
	query_args := args[ndx:]

	db_fpath, err = db_path(cfg.opts.notes_path, a = cfg.alloc.perm)
	defer delete(db_fpath, allocator = cfg.alloc.perm)
	if err != nil {
		fmt.eprintln("failed to produce path to temporary DB")
		return 1
	}

	rc := sqlite.open_v2(
		strings.unsafe_string_to_cstring(db_fpath),
		&db,
		sqlite.Open_Flags{.Readonly},
		nil,
	)
	if rc != .Ok {
		fmt.eprintfln("failed to open db: %s (%v)", sqlite.errmsg(db), rc)
		return 1
	}
	defer sqlite.close(db)

	rc = sqlite.prepare_v2(db, strings.unsafe_string_to_cstring(query), -1, &stmt, nil)
	if rc != .Ok {
		fmt.eprintln("failed to prepare notes insert SQL stmt")
		return 1
	}
	defer sqlite.finalize(stmt)

	// Write query as '"T1" OR "T2" ...'
	// Keeps terms with leading- or trailing asterisk (*) unqoted to
	// support suffix- and prefix searches.
	{
		chkpoint := virtual.arena_temp_begin(&cfg.arenas.tmp)
		defer virtual.arena_temp_end(chkpoint)
		sb, _ := strings.builder_make(allocator = cfg.alloc.tmp)
		for term, i in query_args {
			if i > 0 {
				strings.write_string(&sb, " OR ")
			}
			if len(term) > 1 && strings.has_suffix(term, "*") {
				strings.write_string(&sb, term)
			} else {
				strings.write_byte(&sb, '"')
				for c in term {
					if c == '"' {
						strings.write_byte(&sb, '"')
					}
					strings.write_rune(&sb, c)
				}
				strings.write_byte(&sb, '"')
			}
		}
		search_query, err = strings.clone(strings.to_string(sb), allocator = cfg.alloc.perm)
		strings.builder_destroy(&sb)
	}

	if err != nil {
		fmt.eprintfln("Failed to build query from '%v'", query_args)
		return 1
	}
	defer delete(search_query, allocator = cfg.alloc.perm)

	_ = sql_bind_text(stmt, 1, search_query)
	_ = sqlite.bind_int(stmt, 2, c.int(opts.limit))
	_ = sqlite.bind_int(stmt, 3, c.int(offset))

	results := 0
	fmt.println("```yaml")
	fmt.println("results:")
	for ;; results += 1 {
		rc := sqlite.step(stmt)
		if rc != .Row {
			break
		}

		id := sqlite.column_text(stmt, 0)
		title := sqlite.column_text(stmt, 1)
		keywords := sqlite.column_text(stmt, 2)
		collections := sqlite.column_text(stmt, 3)
		excerpt := sqlite.column_text(stmt, 4)

		fmt.printfln("  - id: %s", id)
		fmt.printfln("    title: %s", title)
		fmt.printfln("    keywords: %s", keywords)
		fmt.printfln("    collections: %s", collections)
		// TODO: limit to 120 chrs
		if len(excerpt) > 0 {
			fmt.printfln("    excerpt: %s", excerpt)
		}

	}
	fmt.println("")
	fmt.printfln("query: %s", search_query)
	fmt.printfln("total_results: %v", results)
	more_results := false
	if results == opts.limit {
		// query
		stmt: sqlite.Stmt
		@(static) query := `
			SELECT count(*)
			FROM notes_fts
			JOIN notes AS n
			ON n.rowid = notes_fts.rowid
			WHERE notes_fts MATCH ?
		`
		rc := sqlite.prepare_v2(db, strings.unsafe_string_to_cstring(query), -1, &stmt, nil)
		if rc != .Ok {
			return 1
		}
		defer sqlite.finalize(stmt)
		_ = sql_bind_text(stmt, 1, search_query)
		_ = sqlite.bind_int(stmt, 2, c.int(opts.limit + 1))
		_ = sqlite.bind_int(stmt, 3, c.int(offset))

		rc = sqlite.step(stmt)
		if rc != .Row {
			return 1
		}
		count := sqlite.column_int64(stmt, 0)
		if count > i64(opts.limit) {
			more_results = true
		}
	}

	fmt.printfln("more_results: %v", more_results)
	fmt.println("```")
	return 0
}

usage_search :: proc() {
	fmt.eprintfln("USAGE: %s search [-l/--limit N] [-p/--page N] QUERY...", PROGNAME)
	fmt.eprintln("")
	fmt.eprintln(
		"Query database for notes containing any of the QUERY words mentioned. Note that words are stemmed before submission and that the `title`, `keywords` and `collections` keys of the note's front-matter metadata is considered during search. Note also that notes are ranked using BM25 according to relevance, meaning uncommon words matter more than common ones. Finally, note that `collections` matches are weighted much more heavily. This means notes whose `collections` key contains one or more QUERY matches are marked highly relevant.",
	)
	fmt.eprintln("")
	fmt.println("Flags:")
	fmt.eprintln("* -l/--limit N")
	fmt.eprintln("  \tLimit number of returned results")
	fmt.eprintln("* -p/--page N")
	fmt.eprintln(
		"  \tIn case of more than LIMIT results, determines which page of results to retrieve (default: 1; most relevant)",
	)
	fmt.eprintln("")
	fmt.eprintln("Output:")
	fmt.eprintln("Returns a fenced YAML block with:")
	fmt.eprintln("- `results` being a list of matches from most- to least relevant.")
	fmt.eprintln("- `total_results` how many results was returned in this query.")
	fmt.eprintln(
		"- `more_results` indicates whether querying again with a higher -p/--page argument will yield more results",
	)

}
