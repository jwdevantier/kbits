// SPDX-FileCopyrightText: 2026 Jesper Wendel Devantier
// SPDX-License-Identifier: BSD-2-Clause
package notes

import "core:fmt"
import "core:testing"
import "core:unicode/utf8"

T :: testing.T

// Helper: assert that `got` equals the expected list `want`.
check_links :: proc(t: ^testing.T, got: [dynamic]WikiLink, want: []WikiLink, msg: string = "") {
	if !testing.expectf(
		t,
		len(got) == len(want),
		"len mismatch: got %v want %v [%s]",
		len(got),
		len(want),
		msg,
	) {
		for i in 0 ..< len(got) {
			fmt.eprintf(
				"  got[%v] = id=%q alias=%q [%v, %v)\n",
				i,
				got[i].id,
				got[i].alias,
				got[i].start,
				got[i].end,
			)
		}
		return
	}
	for i in 0 ..< len(want) {
		g, w := got[i], want[i]
		if !testing.expectf(
			t,
			g == w,
			"link %v mismatch:\n  got:  id=%q alias=%q [%v, %v)\n  want: id=%q alias=%q [%v, %v) [%s]",
			i,
			g.id,
			g.alias,
			g.start,
			g.end,
			w.id,
			w.alias,
			w.start,
			w.end,
			msg,
		) {
			return
		}
	}
}

// ---------------------------------------------------------------------------
// extract_wiki_links
// ---------------------------------------------------------------------------

@(test)
test_empty :: proc(t: ^testing.T) {
	wls := extract_wiki_links("")
	defer delete(wls)
	check_links(t, wls, {}, "empty input")
}

@(test)
test_plain_text :: proc(t: ^testing.T) {
	wls := extract_wiki_links("just some text, no links at all")
	defer delete(wls)
	check_links(t, wls, {}, "no brackets")
}

@(test)
test_simple_wikilink :: proc(t: ^testing.T) {
	wls := extract_wiki_links("[[id]]")
	defer delete(wls)
	check_links(t, wls, {{start = 0, end = 6, id = "id", alias = ""}}, "[[id]]")
}

@(test)
test_aliased_wikilink :: proc(t: ^testing.T) {
	wls := extract_wiki_links("[[id|alias]]")
	defer delete(wls)
	check_links(t, wls, {{start = 0, end = 12, id = "id", alias = "alias"}}, "[[id|alias]]")
}

@(test)
test_multiple_links :: proc(t: ^testing.T) {
	wls := extract_wiki_links("[[a]] and [[b]]")
	defer delete(wls)
	check_links(
		t,
		wls,
		{{start = 0, end = 5, id = "a", alias = ""}, {start = 10, end = 15, id = "b", alias = ""}},
		"[[a]] and [[b]]",
	)
}

@(test)
test_link_with_spaces_and_digits :: proc(t: ^testing.T) {
	wls := extract_wiki_links("[[my note 123]]")
	defer delete(wls)
	check_links(t, wls, {{start = 0, end = 15, id = "my note 123", alias = ""}}, "[[my note 123]]")
}

@(test)
test_link_with_padding_spaces :: proc(t: ^testing.T) {
	wls := extract_wiki_links("[[  spaced  ]]")
	defer delete(wls)
	check_links(t, wls, {{start = 0, end = 14, id = "spaced", alias = ""}}, "[[  spaced  ]]")
}

@(test)
test_aliased_with_padding :: proc(t: ^testing.T) {
	wls := extract_wiki_links("[[id| some alias ]]")
	defer delete(wls)
	check_links(
		t,
		wls,
		{{start = 0, end = 19, id = "id", alias = "some alias"}},
		"[[id| some alias ]]",
	)
}

@(test)
test_link_mid_line :: proc(t: ^testing.T) {
	wls := extract_wiki_links("prefix [[id]] suffix")
	defer delete(wls)
	check_links(t, wls, {{start = 7, end = 13, id = "id", alias = ""}}, "prefix [[id]] suffix")
}

@(test)
test_link_across_lines :: proc(t: ^testing.T) {
	wls := extract_wiki_links("line one\n[[id]]\nline three")
	defer delete(wls)
	check_links(t, wls, {{start = 9, end = 15, id = "id", alias = ""}}, "link on its own line")
}

// ---------------------------------------------------------------------------
// negative cases (should yield no links)
// ---------------------------------------------------------------------------

@(test)
test_single_bracket :: proc(t: ^testing.T) {
	wls := extract_wiki_links("[")
	defer delete(wls)
	check_links(t, wls, {}, "single [")
}

@(test)
test_three_brackets :: proc(t: ^testing.T) {
	wls := extract_wiki_links("[[[")
	defer delete(wls)
	check_links(t, wls, {}, "three [")
}

@(test)
test_single_closing_bracket :: proc(t: ^testing.T) {
	// Regression for issue 3: a lone ']' must not close a wikilink.
	wls := extract_wiki_links("[[id]")
	defer delete(wls)
	check_links(t, wls, {}, "[[id] (single closing)")
}

@(test)
test_unclosed_at_eof :: proc(t: ^testing.T) {
	wls := extract_wiki_links("[[id")
	defer delete(wls)
	check_links(t, wls, {}, "[[id (unclosed)")
}

@(test)
test_unclosed_alias_at_eof :: proc(t: ^testing.T) {
	wls := extract_wiki_links("[[id|alias")
	defer delete(wls)
	check_links(t, wls, {}, "[[id|alias (unclosed)")
}

@(test)
test_alias_newline_before_close :: proc(t: ^testing.T) {
	wls := extract_wiki_links("[[id|alias\n")
	defer delete(wls)
	check_links(t, wls, {}, "[[id|alias\\n (newline before close)")
}

// ---------------------------------------------------------------------------
// code spans / fences: links inside must be ignored
// ---------------------------------------------------------------------------

@(test)
test_link_inside_inline_code :: proc(t: ^testing.T) {
	wls := extract_wiki_links("`[[id]]`")
	defer delete(wls)
	check_links(t, wls, {}, "inline code swallows link")
}

@(test)
test_link_after_inline_code :: proc(t: ^testing.T) {
	wls := extract_wiki_links("`code` [[id]]")
	defer delete(wls)
	check_links(t, wls, {{start = 7, end = 13, id = "id", alias = ""}}, "link after inline code")
}

@(test)
test_link_inside_fenced_block :: proc(t: ^testing.T) {
	// A real fence at column 0; link inside is skipped, link after is captured.
	text := "```\n[[inside]]\n```\n[[outside]]"
	wls := extract_wiki_links(text)
	defer delete(wls)
	check_links(t, wls, {{start = 19, end = 30, id = "outside", alias = ""}}, "fenced block")
}

@(test)
test_mid_line_backticks_not_a_fence :: proc(t: ^testing.T) {
	// Regression for issue 5: ``` after "hello " on the same line is NOT a fence,
	// so the wikilink on the next line must still be found.
	text := "hello ``` not a fence\n[[real]]"
	wls := extract_wiki_links(text)
	defer delete(wls)
	check_links(
		t,
		wls,
		{{start = 22, end = 30, id = "real", alias = ""}},
		"mid-line ``` is inline, not a fence",
	)
}

@(test)
test_fence_swallows_rest_when_unclosed :: proc(t: ^testing.T) {
	// A genuine fence at column 0 that is never closed consumes everything after.
	text := "```\n[[swallowed]]\nno close here"
	wls := extract_wiki_links(text)
	defer delete(wls)
	check_links(t, wls, {}, "unclosed fence eats the rest")
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

@(test)
test_is_letter :: proc(t: ^testing.T) {
	for r in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_" {
		testing.expectf(t, is_letter(r), "expected is_letter(%q)", r)
	}
	for r in "0123456789 .-]" {
		testing.expectf(t, !is_letter(r), "expected !is_letter(%q)", r)
	}
}

@(test)
test_is_digit :: proc(t: ^testing.T) {
	for r in "0123456789" {
		testing.expectf(t, is_digit(r), "expected is_digit(%q)", r)
	}
	for r in "abcABC _ .-]" {
		testing.expectf(t, !is_digit(r), "expected !is_digit(%q)", r)
	}
}

@(test)
test_peek_bounds :: proc(t: ^testing.T) {
	s := "abc"
	testing.expect(t, peek(s, 0) == 'a', "peek(0)")
	testing.expect(t, peek(s, 2) == 'c', "peek(2)")
	testing.expect(t, peek(s, 3) == utf8.RUNE_EOF, "peek at len -> RUNE_EOF")
	testing.expect(t, peek(s, 100) == utf8.RUNE_EOF, "peek past end -> RUNE_EOF")
}

@(test)
test_peek_while :: proc(t: ^testing.T) {
	// Returns the position of the first rune != r (or len(text) if all match / empty).
	testing.expectf(t, peek_while("[[abc", 0, '[') == 2, "got %v", peek_while("[[abc", 0, '['))
	testing.expectf(t, peek_while("[[", 0, '[') == 2, "got %v", peek_while("[[", 0, '['))
	testing.expectf(t, peek_while("abc", 0, '[') == 0, "got %v", peek_while("abc", 0, '['))
	testing.expectf(t, peek_while("", 0, '[') == 0, "got %v", peek_while("", 0, '['))
}

@(test)
test_string_until_anyof :: proc(t: ^testing.T) {
	pos, ch := string_until_anyof("ab`c\n[d", 0, "`\n[")
	testing.expectf(t, pos == 2 && ch == '`', "got pos=%v ch=%q", pos, ch)

	pos, ch = string_until_anyof("nothing here", 0, "`\n[")
	testing.expectf(t, pos == -1, "expected -1, got %v", pos)

	pos, ch = string_until_anyof("ab`c", 2, "`\n[")
	testing.expectf(t, pos == 2 && ch == '`', "got pos=%v ch=%q", pos, ch)
}


// --- content_of tests
@(test)
content_read :: proc(t: ^testing.T) {
	body := content_body("---\ntitle: x\n---\nbody\n")
	testing.expect_value(t, body, "body\n")
}

@(test)
content_read_no_fm_start :: proc(t: ^testing.T) {
	body := content_body("title: x\n---\nbody\n")
	testing.expect_value(t, body, "")
}

@(test)
content_read_no_fm_end :: proc(t: ^testing.T) {
	body := content_body("---\ntitle: x---\nbody\n")
	testing.expect_value(t, body, "")
}
