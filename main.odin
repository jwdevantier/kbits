// SPDX-FileCopyrightText: 2026 Jesper Wendel Devantier
// SPDX-License-Identifier: BSD-2-Clause
package kbits

import "base:runtime"
import "cmds"
import "core:fmt"
import "core:mem"
import "core:mem/virtual"
import "core:os"


parse_global_flags :: proc(args: []string, opts: ^cmds.ProgOpts) -> (ndx: int, ok: bool) {
	i := 0
	for i < len(args) {
		arg := args[i]
		switch arg {
		case "-d", "--dir":
			if i + 1 >= len(args) {
				fmt.eprintfln("error: %s required a value", arg)
				return i, false
			}
			opts.notes_path = args[i + 1]
			i += 2
		case "-v", "--verbose":
			opts.verbose = true
			i += 1
		case:
			return i, true
		}
	}
	return i, true
}

@(private)
print_leaks :: proc(t: mem.Tracking_Allocator, lbl: string) {
	first := false
	for _, entry in t.allocation_map {
		if first && lbl != "" {
			fmt.eprintfln("Leaks in %s", lbl)
		}
		fmt.eprintfln("%v bytes @ %v", entry.size, entry.location)
	}
}

main :: proc() {
	os.exit(do_main())
}

do_main :: proc() -> int {
	args := os.args[1:]
	cfg: cmds.Config

	cfg.alloc.perm = virtual.arena_allocator(&cfg.arenas.perm)
	defer virtual.arena_destroy(&cfg.arenas.perm)
	cfg.alloc.tmp = virtual.arena_allocator(&cfg.arenas.tmp)
	defer virtual.arena_destroy(&cfg.arenas.tmp)

	when ODIN_DEBUG {
		track_perm: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track_perm, cfg.alloc.perm)
		defer {
			print_leaks(track_perm, "permanent allocator")
		}

		track_tmp: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track_tmp, cfg.alloc.tmp)
		defer {
			print_leaks(track_tmp, "temporary allocator")
		}
	}

	ndx, ok := parse_global_flags(args, &cfg.opts)
	if !ok {
		return 1
	}

	subcmd: string
	if ndx >= len(args) {
		subcmd = "help"
	} else {
		subcmd = args[ndx]
	}

	cmdargs: []string
	if ndx + 1 >= len(args) {
		cmdargs = nil
	} else {
		cmdargs = args[ndx + 1:]
	}

	if cfg.opts.notes_path == "" {
		// If notes path is unset, devise the platform-specific default
		arena_temp := virtual.arena_temp_begin(&cfg.arenas.tmp)
		defer virtual.arena_temp_end(arena_temp)
		state_dir, err := os.user_data_dir(cfg.alloc.tmp)
		if err != nil {
			fmt.eprintfln("error: %s", os.error_string(err))
			os.exit(1)
		}
		app_notes_dir: string
		app_notes_dir, err = os.join_path({state_dir, "kbits"}, cfg.alloc.perm)
		if err != nil {
			fmt.eprintfln("error: %s", os.error_string(err))
			os.exit(1)
		}
		cfg.opts.notes_path = app_notes_dir
	}

	if cfg.opts.verbose {
		fmt.eprintfln("Notes directory: '%s'", cfg.opts.notes_path)
	}

	if subcmd != "help" && subcmd != "root" && !os.is_dir(cfg.opts.notes_path) {
		fmt.eprintfln("Error: No directory at '%s'.", cfg.opts.notes_path)
		fmt.eprintln("       Use -d/--dir PATH to specify the notes directory")
		return 1
	}

	switch subcmd {
	case "help":
		os.exit(cmds.help(cmdargs))
	case "index":
		os.exit(cmds.index(&cfg))
	case "read":
		os.exit(cmds.readnote(&cfg, cmdargs))
	case "search":
		os.exit(cmds.search(&cfg, cmdargs))
	case "root":
		fmt.printf(cfg.opts.notes_path)
	case:
		fmt.eprintfln("Unknown subcommand '%s'", subcmd)
		return 1
	}
	return 0
}
