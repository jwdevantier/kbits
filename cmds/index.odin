// SPDX-FileCopyrightText: 2026 Jesper Wendel Devantier
// SPDX-License-Identifier: BSD-2-Clause
package cmds

import "../notes"
import "../sqlite"
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

schema := #load("../schema.sql", string)

index :: proc(cfg: ^Config) -> int {
	tmp_db: string
	err: os.Error
	tmp_db, err = db_path(cfg.opts.notes_path, name = "tmp.db", a = cfg.alloc.perm)
	if err != nil {
		fmt.eprintln("failed to produce path to temporary DB")
		return 1
	}
	defer delete(tmp_db, allocator = cfg.alloc.tmp)

	meta_dir := os.dir(tmp_db)
	err = mkdir_p(meta_dir, exists_ok = true)
	if err != nil {
		fmt.eprintfln("failed to create _meta folder in '%s' (%s)", meta_dir, os.error_string(err))
		return 1
	}

	if os.exists(tmp_db) {
		err := os.remove(tmp_db)
		if err != nil {
			fmt.eprintln("existing tmp DB")
			return 1
		}
	}

	db: sqlite.sqlite3
	rc := sqlite.open_v2(
		strings.unsafe_string_to_cstring(tmp_db),
		&db,
		sqlite.Open_Flags{.Read_Write, .Create},
		nil,
	)
	if rc != .Ok {
		fmt.eprintfln("failed to open new DB for indexing: %s (%v)", sqlite.errmsg(db), rc)
		return 1
	}
	defer sqlite.close(db)

	errmsg: ^cstring
	rc = sqlite.exec(db, strings.unsafe_string_to_cstring(schema), nil, nil, errmsg)
	defer sqlite.free(errmsg)
	if rc != .Ok {
		fmt.eprintln("error applying schema: %s", errmsg)
		return 1
	}

	entries: []os.File_Info
	entries, err = os.read_all_directory_by_path(cfg.opts.notes_path, cfg.alloc.tmp)
	if err != nil {
		fmt.eprintln("failed to list notes directory")
		return 1
	}

	if ok := index_stage_1(db, entries, cfg.opts.notes_path, a = cfg.alloc.tmp); !ok {
		return 1
	}

	if ok := index_stage_2(db, entries, cfg.opts.notes_path, a = cfg.alloc.tmp); !ok {
		return 1
	}

	if ok := index_stage_3(db); !ok {
		return 1
	}

	db_dest: string
	db_dest, err = db_path(cfg.opts.notes_path, a = cfg.alloc.perm)
	defer delete(db_dest, allocator = cfg.alloc.perm)
	if err != nil {
		fmt.eprintln("failed to produce path to temporary DB")
		return 1
	}
	if (os.is_file(db_dest)) {
		err = os.remove(db_dest)
		if err != nil {
			fmt.eprintfln("failed to remove existing DB")
			return 1
		}
	}
	err = os.rename(tmp_db, db_dest)
	if err != nil {
		fmt.eprintfln("failed to install tmp_db as new DB")
		return 1
	}

	return 0
}

@(private)
index_stage_1 :: proc(
	db: sqlite.sqlite3,
	entries: []os.File_Info,
	notes_path: string,
	a: runtime.Allocator,
) -> bool {
	rc: sqlite.Result_Code
	buf: [4095]u8 // scratch buffer for note reads
	stmt: sqlite.Stmt

	@(static) query := `
		INSERT INTO notes (id, title, keywords, collections, excerpt)
		VALUES (?, ?, ?, ?, ?)
	`
	rc = sqlite.prepare_v2(db, strings.unsafe_string_to_cstring(query), -1, &stmt, nil)
	if rc != .Ok {
		fmt.eprintln("failed to prepare notes insert SQL stmt")
		return false
	}
	defer sqlite.finalize(stmt)

	for fi in entries {
		#partial switch fi.type {
		case .Directory:
			switch (fi.name) {
			case "_meta":
			case ".git":
			case:
				fmt.eprintfln(
					"Warning: directory '%s' in notes directory is not being indexed. Subdirectories are not allowed.",
					fi.name,
				)
			}
		case .Regular:
			if !strings.has_suffix(fi.name, ".md") {
				continue
			}
			abs_fpath, aerr := filepath.join({notes_path, fi.name}, allocator = a)
			if aerr != nil {
				fmt.eprintln("failed to allocate memory for full file path")
				return false
			}

			data: []byte
			{
				fh, err := os.open(abs_fpath)
				if err != nil {
					fmt.eprintln("failed to open note")
					return false
				}
				defer os.close(fh)
				n, rerr := os.read(fh, buf[:])
				if rerr != nil {
					continue
				}
				data = buf[:n]
			}

			bn := notes.skip_utf8_bom(data)
			if bn != 0 {
				data = data[bn:]
			}
			fms, fme := notes.find_fm_range(data)
			if fme < 0 {
				fmt.eprintfln("cannot find front-matter in note '%s', skipping", fi.name)
				continue
			}

			fm, fm_err := notes.parse_frontmatter(data[fms:fme], a = a)
			if fm_err != nil {
				fmt.eprintfln("cannot parse front-matter in note '%s', skipping", fi.name)
				continue
			}

			if missing := notes.validate_fm_keys(fm); missing != "" {
				fmt.eprintfln(
					"front-matter in note '%s' missing required key '%s'",
					fi.name,
					missing,
				)
				continue
			}

			note_id := filepath.stem(fi.name)

			_ = sql_bind_text(stmt, 1, note_id)
			_ = sql_bind_text(stmt, 2, fm["title"])
			_ = sql_bind_text(stmt, 3, fm["keywords"])
			_ = sql_bind_text(stmt, 4, fm["collections"])
			_ = sql_bind_text(stmt, 5, fm["excerpt"])

			rc := sqlite.step(stmt)
			if rc != .Done {
				fmt.eprintfln("insert failed for %s: %s", note_id, sqlite.errmsg(db))
			}
			_ = sqlite.reset(stmt)
			_ = sqlite.clear_bindings(stmt)
		case:
			continue
		}
	}
	return true
}

@(private)
index_stage_2 :: proc(
	db: sqlite.sqlite3,
	entries: []os.File_Info,
	notes_path: string,
	a: runtime.Allocator,
) -> bool {
	err: os.Error
	stmt: sqlite.Stmt

	@(static) query := `
		INSERT INTO edges (source_id, target_id) VALUES (?, ?)
	`

	rc := sqlite.prepare_v2(db, strings.unsafe_string_to_cstring(query), -1, &stmt, nil)
	if rc != .Ok {
		fmt.eprintln("failed to prepare notes insert SQL stmt")
		return false
	}
	defer sqlite.finalize(stmt)

	for fi in entries {
		abs_fpath: string
		content: []byte

		if fi.type != .Regular {
			continue
		}

		abs_fpath, err = filepath.join({notes_path, fi.name}, allocator = a)
		defer delete(abs_fpath, allocator = a)
		content, err = os.read_entire_file(abs_fpath, allocator = a)
		defer delete(content, allocator = a)

		source_id := filepath.stem(fi.name)

		md := notes.content_body(content)
		links := notes.extract_wiki_links(md, a = a)
		for link in links {
			_ = sql_bind_text(stmt, 1, source_id)
			_ = sql_bind_text(stmt, 2, link.id)

			rc := sqlite.step(stmt)
			if rc != .Done {
				fmt.eprintfln(
					"edge table insert failed for note '%s' (%s)",
					source_id,
					sqlite.errmsg(db),
				)
			}
			_ = sqlite.reset(stmt)
			_ = sqlite.clear_bindings(stmt)
		}
	}
	return true
}

index_stage_3 :: proc(db: sqlite.sqlite3) -> bool {
	err: os.Error
	@(static) query := `
		INSERT INTO notes_fts (notes_fts) VALUES('rebuild')
	`
	errmsg: ^cstring
	rc := sqlite.exec(db, strings.unsafe_string_to_cstring(query), nil, nil, errmsg)
	defer sqlite.free(errmsg)
	if rc != .Ok {
		fmt.eprintln("failed to populate notes_fts (%s)", sqlite.errmsg(db))
		return false
	}

	return true
}

usage_index :: proc() {
	fmt.eprintfln("USAGE: %s index", PROGNAME)
	fmt.eprintln("")
	fmt.eprintln(
		"Recreates the database which indexes note metadata and which is used for `search` requests. Run whenever you have added/removed/altered notes and want those changes reflected in your searches.",
	)
	fmt.eprintln("")
	fmt.eprintln("Exit codes:")
	fmt.eprintln(" 0 (on success; database was (re-)indexed)")
	fmt.eprintln(" 1 (on error; see program output for details)")
}
