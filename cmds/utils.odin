// SPDX-FileCopyrightText: 2026 Jesper Wendel Devantier
// SPDX-License-Identifier: BSD-2-Clause
package cmds
import "../sqlite"
import "base:runtime"
import "core:c"
import "core:mem/virtual"
import "core:os"
import "core:path/filepath"
import "core:strings"

PROGNAME := "kbits"

ProgOpts :: struct {
	notes_path: string,
	verbose:    bool,
}

Config :: struct {
	opts:   ProgOpts,
	arenas: struct {
		perm: virtual.Arena,
		tmp:  virtual.Arena,
	},
	alloc:  struct {
		perm: runtime.Allocator,
		tmp:  runtime.Allocator,
	},
}

@(private)
sql_bind_text :: proc(stmt: sqlite.Stmt, pos: c.int, val: string) -> sqlite.Result_Code {
	if len(val) == 0 do return sqlite.bind_null(stmt, pos)
	return sqlite.bind_text(
		stmt,
		pos,
		strings.unsafe_string_to_cstring(val),
		c.int(len(val)),
		sqlite.Transient,
	)
}


@(private)
mkdir_p :: proc(path: string, exists_ok: bool = true) -> os.Error {
	if exists_ok && os.is_directory(path) {
		return nil
	}
	return os.make_directory_all(path)
}

@(private)
db_path :: proc(
	notes_path: string,
	name: string = "db.db",
	a: runtime.Allocator = context.allocator,
) -> (
	string,
	os.Error,
) {
	return filepath.join([]string{notes_path, "_meta", "db", name}, allocator = a)
}
