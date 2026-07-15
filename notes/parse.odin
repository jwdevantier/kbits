// SPDX-FileCopyrightText: 2026 Jesper Wendel Devantier
// SPDX-License-Identifier: BSD-2-Clause
package notes
import "base:runtime"
import "core:strings"
import "core:unicode/utf8"

/*
	Return view into the provided `content` corresponding
	to the body of content containing a front-matter.
*/
content_body :: proc {
	content_body_of_string,
	content_body_of_bytes,
}

content_body_of_string :: proc(content: string) -> string {
	return content_body_of_bytes(transmute([]byte)content)
}
content_body_of_bytes :: proc(content: []byte) -> string {
	bs := transmute([]byte)content

	fs, fe := find_fm_range(bs)
	if fe < 0 {
		return ""
	}
	return transmute(string)bs[fe + len(NL_DASHES) + 1:]
}

/*
	parses `text` as markdown, returning a list of every Wiki-style link
	([[link]] and [[link|text]]) not inside a inline- or fenced code
	block.

	Returns an owned dynamic array of WikiLinks entries

	NOTE: cm allows inline code spans using one OR MORE backticks on either side.
		  this supports just one
	NOTE: cm allows up to 3 leading spaces before the code fence begin/close tags,
		  this does not.
*/
extract_wiki_links :: proc(
	text: string,
	a: runtime.Allocator = context.allocator,
) -> [dynamic]WikiLink {
	wls := make([dynamic]WikiLink, context.allocator)

	// must track state (Normal/Inline_Code/Code_Block)
	fl := true
	pos := 0
	ch: rune
	end := len(text)
	ok: bool
	for pos < end {
		pos, ch = string_until_anyof(text, pos, "`\n[")
		if pos < 0 {
			pos = end
			break
		}
		fl = pos == 0 || text[pos - 1] == '\n'
		switch (ch) {
		case '`':
			// if on a fresh line, check if we have a fence
			if fl && string_has_prefix_abs(text, pos, FENCE) {
				pos, ok = skip_fence(text, pos)
				if !ok {
					// unclosed, covers rest of text
					pos = end
					break
				}
				continue
			} else {
				// inline code span
				// TODO: it is actually valid CM to have spans using one OR MORE backticks, closed by an equal number
				pos += 1 // consume '`'
				pos, ch = string_until_anyof(text, pos, "\n`")
				if pos < 0 {
					pos = end
					break
				}
				pos += 1
				switch (ch) {
				case '`':
					continue
				case '\n':
					continue
				}
			}
		case '\n':
			pos += 1
		case '[':
			// TODO: check for wikilink
			wl_start := pos
			pos = peek_while(text, pos, '[')
			if pos - wl_start != 2 {
				continue
			}
			lbl_start := pos
			for ch, ndx in text[pos:] {
				if is_letter(ch) || is_digit(ch) || ch == ' ' do continue
				pos += ndx
				break
			}
			if (pos == end) {
				break
			}
			lbl_end := pos
			ch = peek(text, pos)
			switch (ch) {
			case utf8.RUNE_EOF:
				pos = end
				break
			case ']':
				if (peek(text, pos + 1) != ']') {
					// not a wikilink
					pos += 1
					continue
				}
				// => [[<note id>]] type link
				pos += 2
				append(
					&wls,
					WikiLink {
						start = wl_start,
						end = pos,
						id = strings.trim(text[lbl_start:lbl_end], cutset = " "),
						alias = "",
					},
				)
				continue
			case '|':
				// alias
				pos += 1
				alias_start := pos
				pos, ch = string_until_anyof(text, pos, "]\n")
				if pos < 0 {
					pos = end
					break
				}
				if ch == '\n' || peek(text, pos + 1) != ']' {
					pos += 1
					continue
				}
				alias_end := pos
				pos += 2 // ']]'
				append(
					&wls,
					WikiLink {
						start = wl_start,
						end = pos,
						id = strings.trim(text[lbl_start:lbl_end], cutset = " "),
						alias = strings.trim(text[alias_start:alias_end], cutset = " "),
					},
				)

			case:
				continue
			}
		// OK, opening brackets found, no
		}
	}
	return wls
}

/*
	ONLY call when at a position where a fence starts
	NOTE: if returns -1, fence never closed. Consume rest of content
*/
skip_fence :: proc(text: string, pos: int) -> (int, bool) {
	assert(string_has_prefix_abs(text, pos, FENCE), "invalid call")
	pos := pos + len(FENCE)
	npos := string_index_abs(text, pos, "\n")
	if npos < 0 {
		return -1, false
	}
	pos = npos + 1
	// inside fence, FL
	fep := string_index_abs(text, pos, NL_FENCE)
	if fep < 0 {
		// fence never closed
		return -1, false
	}
	pos = fep + len(NL_FENCE)
	// TODO: a little too permissive, we allow anything trailing the close until newline
	npos = string_index_abs(text, pos, "\n")
	if npos < 0 {
		// consume rest of string
		return len(text), true
	}
	return npos + 1, true
}

string_until_anyof :: proc(text: string, pos: int, chrs: string) -> (int, rune) {
	for ch, off in text[pos:] {
		for tch in chrs {
			if tch == ch do return pos + off, tch
		}
	}
	return -1, 0
}

/*
	NOTE: returns utf8.RUNE_EOF if request is out of bounds.
 */
peek :: proc(text: string, pos: int) -> rune {
	if pos < len(text) {
		return utf8.rune_at(text, pos)
	}
	return utf8.RUNE_EOF
}

peek_while :: proc(text: string, pos: int, r: rune) -> int {
	for ch, ndx in text[pos:] {
		if ch != r do return ndx + pos
	}
	return len(text)
}

is_letter :: proc(r: rune) -> bool {
	return ('a' <= r && r <= 'z') || ('A' <= r && r <= 'Z') || r == '_'
}

is_digit :: proc(r: rune) -> bool {
	return '0' <= r && r <= '9'
}

peek_until :: proc(text: string, pos: int, r: rune) -> int {
	for ch, ndx in text[pos:] {
		if ch == r do return ndx + pos
	}
	return -1
}

@(private)
string_has_prefix_abs :: proc(text: string, off: int, substr: string) -> bool {
	return strings.has_prefix(text[off:], substr)
}

@(private)
string_index_abs :: proc(text: string, off: int, substr: string) -> int {
	prel := strings.index(text[off:], substr)
	if prel < 0 {
		return -1
	}
	return off + prel
}

@(private)
FENCE :: "```"
@(private)
NL_FENCE :: "\n```"

WikiLink :: struct {
	start, end: int,
	id:         string,
	alias:      string,
}
