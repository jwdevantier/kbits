// SPDX-FileCopyrightText: 2026 Jesper Wendel Devantier
// SPDX-License-Identifier: BSD-2-Clause
package cmds
import "../notes"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

readnote :: proc(cfg: ^Config, args: []string) -> int {
	note_path: string
	note_fname: string
	err: os.Error

	if len(args) != 1 {
		usage_readnote()
		return 1
	}

	note_fname, err = strings.join([]string{args[0], ".md"}, sep = "", allocator = cfg.alloc.perm)
	if err != nil {
		fmt.eprintln("failed to allocate string for note's filename")
		return 1
	}
	defer delete(note_fname, allocator = cfg.alloc.perm)

	note_path, err = filepath.join(
		[]string{cfg.opts.notes_path, note_fname},
		allocator = cfg.alloc.perm,
	)
	if err != nil {
		fmt.eprintln("failed to allocate string for note's file path")
		return 1
	}
	defer delete(note_path, allocator = cfg.alloc.perm)

	if !os.is_file(note_path) {
		fmt.eprintfln("No note by id '%s' found", args[0])
		return 2
	}

	data: []byte
	data, err = os.read_entire_file(note_path, allocator = cfg.alloc.perm)
	if err != nil {
		fmt.eprintfln("Failed to read note '%s'", note_path)
		return 1
	}

	bn := notes.skip_utf8_bom(data)
	if bn != 0 {
		data = data[bn:]
	}

	s := transmute(string)data
	fmt.println(s)

	return 0
}

usage_readnote :: proc() {
	fmt.eprintfln("USAGE: %s read NOTE_ID", PROGNAME)
	fmt.eprintln("")
	fmt.eprintfln("Returns contents of requested note on stdout.")
	fmt.eprintln("")
	fmt.eprintln("Exit codes:")
	fmt.eprintln(" 0 (on success; note was found)")
	fmt.eprintln(" 1 (on error; general error)")
	fmt.eprintln(" 2 (on error; note does not exist)")
}
