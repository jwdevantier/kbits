// SPDX-FileCopyrightText: 2026 Jesper Wendel Devantier
// SPDX-License-Identifier: BSD-2-Clause
package notes

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

// Zero-copy view of a (static) string literal as []byte. The literal lives for
// the whole program, so views into it stay valid for the test's duration.
bytes_of :: proc(s: string) -> []byte {return transmute([]byte)s}

// ---- find_fm_range ----------------------------------------------------------
// The fence finder is the foundation; these cover the cases we labored over.

@(test)
fm_range_lf :: proc(t: ^testing.T) {
	fs, fe := find_fm_range(bytes_of("---\ntitle: x\n---\nbody\n"))
	testing.expect_value(t, fs, 4) // first byte after the opening fence line
	testing.expect_value(t, fe, 12) // the '\n' that precedes the closing '---'
}

@(test)
fm_range_crlf :: proc(t: ^testing.T) {
	fs, fe := find_fm_range(bytes_of("---\r\ntitle: x\r\n---\r\nbody\r\n"))
	testing.expect_value(t, fs, 5) // '---\r\n' is 5 bytes
	testing.expect_value(t, fe, 14) // the '\n' of the '\r\n' before closing '---'
}

@(test)
fm_range_trailing_ws_on_fences :: proc(t: ^testing.T) {
	// '---  ' and '---\t' must still count as fence lines.
	fs, fe := find_fm_range(bytes_of("---  \ntitle: x\n---\t\nbody\n"))
	testing.expect_value(t, fs, 6)
	testing.expect_value(t, fe, 14)
}

@(test)
fm_range_mid_line_dashes :: proc(t: ^testing.T) {
	// '---' mid-line (preceded by a space, not '\n') must NOT be taken as the close.
	fs, fe := find_fm_range(bytes_of("---\ntitle: a --- b\n---\nbody\n"))
	testing.expect_value(t, fs, 4)
	testing.expect_value(t, fe, 18)
}

@(test)
fm_range_no_opening_fence :: proc(t: ^testing.T) {
	fs, fe := find_fm_range(bytes_of("# just markdown\nno fences\n"))
	testing.expect_value(t, fs, -1)
	testing.expect_value(t, fe, -1)
}

@(test)
fm_range_opened_but_unclosed :: proc(t: ^testing.T) {
	// Opening fence present, no closing '---' anywhere -> fm_start set, fm_end -1.
	fs, fe := find_fm_range(bytes_of("---\ntitle: x\nbody never closes\n"))
	testing.expect_value(t, fs, 4)
	testing.expect_value(t, fe, -1)
}

@(test)
fm_range_junk_after_opening_dashes :: proc(t: ^testing.T) {
	// '---x' is not a clean fence line -> not front-matter at all.
	fs, fe := find_fm_range(bytes_of("---x\ntitle: y\n---\nbody\n"))
	testing.expect_value(t, fs, -1)
	testing.expect_value(t, fe, -1)
}

// ---- find_md_offset ---------------------------------------------------------

@(test)
md_offset_lf :: proc(t: ^testing.T) {
	testing.expect_value(t, find_md_offset(bytes_of("---\ntitle: x\n---\nbody\n")), 17)
}

@(test)
md_offset_crlf :: proc(t: ^testing.T) {
	testing.expect_value(t, find_md_offset(bytes_of("---\r\ntitle: x\r\n---\r\nbody\r\n")), 20)
}

@(test)
md_offset_none :: proc(t: ^testing.T) {
	testing.expect_value(t, find_md_offset(bytes_of("# no front-matter\n")), -1)
	testing.expect_value(t, find_md_offset(bytes_of("---\ntitle: x\nnever closes\n")), -1)
}

// ---- parse_frontmatter ------------------------------------------------------

@(test)
fm_parse_basic :: proc(t: ^testing.T) {
	m, err := parse_frontmatter(
		bytes_of("title: my note\n\n# a full-line comment\nkeywords: a b c\n"),
		context.allocator,
	)
	defer {if m != nil {delete(m)}}
	if !testing.expect_value(t, err, FM_Error.Ok) do return
	testing.expect_value(t, m["title"], "my note")
	testing.expect_value(t, m["keywords"], "a b c")
	_, is_key := m["a full-line comment"]
	testing.expect(t, !is_key, "comment line must not become a key")
}

@(test)
fm_parse_value_with_hash_verbatim :: proc(t: ^testing.T) {
	// No trailing-comment stripping: '#' in a value is literal.
	m, err := parse_frontmatter(bytes_of("title: C# tips\n"), context.allocator)
	defer {if m != nil {delete(m)}}
	if !testing.expect_value(t, err, FM_Error.Ok) do return
	testing.expect_value(t, m["title"], "C# tips")
}

@(test)
fm_parse_value_with_colon :: proc(t: ^testing.T) {
	// Split on the FIRST colon only.
	m, err := parse_frontmatter(bytes_of("url: http://example.com:80\n"), context.allocator)
	defer {if m != nil {delete(m)}}
	if !testing.expect_value(t, err, FM_Error.Ok) do return
	testing.expect_value(t, m["url"], "http://example.com:80")
}

@(test)
fm_parse_duplicate_keys :: proc(t: ^testing.T) {
	m, err := parse_frontmatter(bytes_of("title: a\ntitle: b\n"), context.allocator)
	defer {if m != nil {delete(m)}}
	if !testing.expect_value(t, err, FM_Error.Ok) do return
	testing.expect_value(t, m["title"], "b") // last wins
}

@(test)
fm_parse_empty_value :: proc(t: ^testing.T) {
	// 'title:' with nothing after is stored as "" (not malformed); validate catches it.
	m, err := parse_frontmatter(bytes_of("title:\n"), context.allocator)
	defer {if m != nil {delete(m)}}
	if !testing.expect_value(t, err, FM_Error.Ok) do return
	testing.expect_value(t, m["title"], "")
}

@(test)
fm_parse_malformed :: proc(t: ^testing.T) {
	// no-colon, non-comment line
	m1, e1 := parse_frontmatter(bytes_of("title: x\ngarbage line\n"), context.allocator)
	defer {if m1 != nil {delete(m1)}}
	testing.expect_value(t, e1, FM_Error.Malformed)

	// empty key
	m2, e2 := parse_frontmatter(bytes_of(": foo\n"), context.allocator)
	defer {if m2 != nil {delete(m2)}}
	testing.expect_value(t, e2, FM_Error.Malformed)
}

// ---- validate_fm_keys -------------------------------------------------------

@(test)
validate_fm_keys_cases :: proc(t: ^testing.T) {
	// present
	m1 := make(map[string]string, allocator = context.allocator)
	defer delete(m1)
	m1["title"] = "x"
	testing.expect_value(t, validate_fm_keys(m1), "")

	// missing entirely
	m2 := make(map[string]string, allocator = context.allocator)
	defer delete(m2)
	testing.expect_value(t, validate_fm_keys(m2), "title")

	// present but empty
	m3 := make(map[string]string, allocator = context.allocator)
	defer delete(m3)
	m3["title"] = ""
	testing.expect_value(t, validate_fm_keys(m3), "title")
}

// ---- skip_utf8_bom ----------------------------------------------------------

@(test)
skip_bom_cases :: proc(t: ^testing.T) {
	testing.expect_value(t, skip_utf8_bom(bytes_of("\xEF\xBB\xBF---\ntitle: x\n")), 3)
	testing.expect_value(t, skip_utf8_bom(bytes_of("---\ntitle: x\n")), 0)
	testing.expect_value(t, skip_utf8_bom(bytes_of("\xEF\xBB")), 0) // too short to be a BOM
}

// ---- read_note_frontmatter (integration: real file, BOM, wiring) -----------

@(test)
read_note_with_bom :: proc(t: ^testing.T) {
	path := must_tmp_path()
	defer delete(path)
	defer os.remove(path)
	werr := os.write_entire_file(
		path,
		bytes_of("\xEF\xBB\xBF---\ntitle: bom note\nkeywords: a b\n---\n# body\n"),
	)
	if !testing.expect(t, werr == nil, "setup: write failed") do return

	buf: [4096]byte
	fields, err := read_note_frontmatter(path, buf[:], context.allocator)
	defer {if fields != nil {delete(fields)}}
	if !testing.expect_value(t, err, FM_Error.Ok) do return
	testing.expect_value(t, fields["title"], "bom note")
	testing.expect_value(t, fields["keywords"], "a b")
}

@(test)
read_note_no_fm :: proc(t: ^testing.T) {
	path := must_tmp_path()
	defer delete(path)
	defer os.remove(path)
	werr := os.write_entire_file(path, bytes_of("# just markdown\nno front-matter here\n"))
	if !testing.expect(t, werr == nil, "setup: write failed") do return

	buf: [4096]byte
	fields, err := read_note_frontmatter(path, buf[:], context.allocator)
	defer {if fields != nil {delete(fields)}}
	testing.expect_value(t, err, FM_Error.Missing)
}

@(test)
read_note_unclosed_is_too_large :: proc(t: ^testing.T) {
	// Taxonomy: opening fence present but no closing fence in the chunk read -> Too_Large
	// (Malformed is reserved for bad FM *content*, not missing close).
	path := must_tmp_path()
	defer delete(path)
	defer os.remove(path)
	werr := os.write_entire_file(path, bytes_of("---\ntitle: x\nbody never closes\n"))
	if !testing.expect(t, werr == nil, "setup: write failed") do return

	buf: [4096]byte
	fields, err := read_note_frontmatter(path, buf[:], context.allocator)
	defer {if fields != nil {delete(fields)}}
	testing.expect_value(t, err, FM_Error.Too_Large)
}

@(test)
read_note_missing_file :: proc(t: ^testing.T) {
	buf: [4096]byte

	// Create a temp file just to reserve a unique path, then remove it so the
	// subsequent read hits a genuinely missing file.
	fname := must_tmp_path()
	defer delete(fname)
	os.remove(fname)

	fields, err := read_note_frontmatter(fname, buf[:], context.allocator)
	defer {if fields != nil {delete(fields)}}
	testing.expect_value(t, err, FM_Error.IO_Error)
}

// ---- Helpers
@(private)
must_tmp_file :: proc() -> ^os.File {
	f, err := os.create_temp_file("", "tmp_*.md")
	if err != nil {
		runtime.panic("tmp_file call failed")
	}
	return f
}

/*
	Returns an owned, unique path in the system's temp directory
*/
@(private)
must_tmp_path :: proc(a: runtime.Allocator = context.allocator) -> string {
	fh := must_tmp_file()
	defer os.close(fh)
	return strings.clone(os.name(fh), a)
}
