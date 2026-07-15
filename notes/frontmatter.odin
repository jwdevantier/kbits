// SPDX-FileCopyrightText: 2026 Jesper Wendel Devantier
// SPDX-License-Identifier: BSD-2-Clause
package notes
import "base:runtime"
import "core:bytes"
import "core:os"
import "core:strings"

FM_Error :: enum {
	Ok,
	Missing,
	Malformed,
	Too_Large,
	Alloc_Err,
	IO_Error,
}

REQUIRED_FM_KEYS :: []string{"title"}

/*
	Read note front-matter. Must exist within
	length of provided buffer.

	NOTE: keys and values are references directly into the provided `buf`
		  buffer. Make a deep copy if lifetimes of values and buffer diverge.
*/
read_note_frontmatter :: proc(
	path: string,
	buf: []byte,
	a: runtime.Allocator = context.allocator,
) -> (
	fields: map[string]string,
	err: FM_Error,
) {
	f: ^os.File
	oserr: os.Error
	f, oserr = os.open(path)
	if oserr != nil {
		return nil, .IO_Error
	}

	n, rerr := os.read(f, buf)
	_ = os.close(f)
	if rerr != nil {
		return nil, .IO_Error
	}

	data := buf[:n]

	if n := skip_utf8_bom(data); n > 0 {
		data = data[n:]
	}

	start, end := find_fm_range(data)
	if end < 0 {
		return nil, .Missing if start == -1 else .Too_Large
	}

	return parse_frontmatter(data[start:end], a)
}

/*
	Parse front-matter content and return a map of key-value entries.

	This is a limited YAML parser. It only supports
	- "empty" lines (empty or with whitespace only)
	- line comments
	- 'foo: bar' entries where both foo and bar are unquoted strings

	NOTE: keys and values are references directly into the provided `fm`
		  buffer. Make a deep copy if lifetimes of values and buffer diverge.
*/
parse_frontmatter :: proc(
	fm: []byte,
	a: runtime.Allocator = context.allocator,
) -> (
	_unused: map[string]string,
	err: FM_Error = nil,
) {
	result := make(map[string]string, allocator = a)
	defer {
		if err != nil {
			delete(result)
		}
	}

	fmtxt := string(fm)
	lines, alloc_err := strings.split_lines(fmtxt, allocator = a)
	if alloc_err != nil {
		return nil, .Alloc_Err
	}
	defer delete(lines, allocator = a)

	for line in lines {
		trimmed := strings.trim_space(line)
		if len(trimmed) == 0 do continue

		colon := strings.index_byte(trimmed, ':')
		if colon < 0 {
			if trimmed[0] == '#' {continue} 	// line comment
			return nil, .Malformed
		}

		key := strings.trim_space(trimmed[:colon])
		if len(key) == 0 {
			return nil, .Malformed
		}

		value := strings.trim_space(trimmed[colon + 1:])

		result[key] = value
	}
	return result, .Ok
}

find_md_offset :: proc(data: []byte) -> int {
	_, fm_end := find_fm_range(data)
	if fm_end < 0 {
		return -1
	}

	i := fm_end + len(NL_DASHES)
	if n := skip_line_end(data, i); n < 1 {
		return -1
	} else {
		return n
	}
}

/*
	Find front-matter section in buffer.

	A front-matter is defined as a section at the start of the buffer
	which is surrounded by lines starting with `---` followed by optional whitespace and a line terminator.

	NOTE: to check if a front-matter section was found, it is sufficient to test that fm_end != -1
*/
find_fm_range :: proc(data: []byte) -> (fm_start := -1, fm_end := -1) {
	i := 0

	if !bytes.has_prefix(data[i:], DASHES) {
		return
	}

	i += len(DASHES)
	if n := skip_line_end(data, i); n < 1 {
		return
	} else {
		i = n
	}
	fm_start = i

	if n := bytes.index(data[i:], NL_DASHES); n < 0 {
		return
	} else {
		i += n
	}
	fm_end = i

	return
}

DASHES :: []byte{'-', '-', '-'}
NL_DASHES :: []byte{'\n', '-', '-', '-'}

skip_line_end :: proc(buf: []byte, pos: int) -> int {
	pos := pos
	for pos < len(buf) {
		switch (buf[pos]) {
		case ' ', '\t', '\r':
			pos += 1
		case '\n':
			return pos + 1
		case:
			return -1
		}
	}
	return -1
}

/*
	Return number of bytes to skip.
	NOTE: Will only skip UTF-8 BOM so returns either 0 or 3
*/
skip_utf8_bom :: proc(buf: []byte) -> int {
	if len(buf) >= 3 && buf[0] == 0xEF && buf[1] == 0xBB && buf[2] == 0xBF {
		// UTF-8 BOM detected
		return 3
	}
	return 0
}

error_string :: proc(e: FM_Error) -> string {
	switch (e) {
	case .Missing:
		return "no front-matter found"
	case .Malformed:
		return(
			"invalid front-matter. Only empty lines, line comments and 'key: value' pairs of uncommented strings are supported" \
		)
	case .Too_Large:
		return "front-matter larger than accepted"
	case .Ok:
		return ""
	case .IO_Error:
		return "error while attempting to read the note"
	case .Alloc_Err:
		return "error allocating memory"
	}
	return ""
}

/*
	Validate front matter contains required fields.

	if missing := validate_fm_keys(fm); missing != "" {
		// handle error
	}

	NOTE: returns first missing property found. If returned value is "", no errors.
*/
validate_fm_keys :: proc(fm: map[string]string) -> string {
	for k in REQUIRED_FM_KEYS {
		v, ok := fm[k]
		if !ok || len(v) == 0 {return k}
	}
	return ""
}
