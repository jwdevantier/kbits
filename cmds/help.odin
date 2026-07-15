// SPDX-FileCopyrightText: 2026 Jesper Wendel Devantier
// SPDX-License-Identifier: BSD-2-Clause
package cmds
import "core:fmt"

help :: proc(args: []string) -> int {
	subcmd := "help" if len(args) == 0 else args[0]

	switch subcmd {
	case "help":
		usage_help()
	case "index":
		usage_index()
	case "read":
		usage_readnote()
	case "search":
		usage_search()
	case:
		fmt.eprintfln("Error: No subcommand named '%s'", subcmd)
		fmt.eprintln("")
		usage_help()
		return 1
	}
	return 0
}

usage_help :: proc() {
	fmt.eprintfln("USAGE: %s help [subcommand]", PROGNAME)
	fmt.eprintln("")
	fmt.eprintfln(
		"Displays help on using the specified subcommand, if any, otherwise, prints this general text.",
	)
	fmt.eprintln("")
	fmt.eprintln("Global flags:")
	fmt.eprintln("* -d/--dir DIRECTORY")
	fmt.eprintln("  \tPath to the directory of notes")
	fmt.eprintln("* -v/--verbose")
	fmt.eprintln("  \tPrint more output than usual")
	fmt.eprintln("")
	fmt.eprintln("")
	fmt.eprintln("Available subcommands:")
	fmt.eprintln("* index")
	fmt.eprintln("  \tRecreate the database servicing searches")
	fmt.eprintln("  \tDo this when you have added or changed notes")
	fmt.eprintln("* read NOTE_ID")
	fmt.eprintln("  \tRetrieve contents of specified note")
	fmt.eprintln("* search [-l/--limit N] [-p/--page N] QUERY...")
	fmt.eprintln("  \tRetrieve a page of search results for notes matching QUERY")
	fmt.eprintln("  \torganized by their relevance (most to least)")
}
