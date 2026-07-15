// SPDX-FileCopyrightText: 2026 Jesper Wendel Devantier
// SPDX-License-Identifier: BSD-2-Clause
package sqlite

import "core:c"

foreign import lib "system:sqlite3"

sqlite3 :: distinct rawptr
Stmt :: distinct rawptr

Result_Code :: enum c.int {
	Ok         = 0,
	Error      = 1,
	Internal   = 2,
	Perm       = 3,
	Abort      = 4,
	Busy       = 5,
	Locked     = 6,
	No_Mem     = 7,
	Readonly   = 8,
	Interrupt  = 9,
	IO_Err     = 10,
	Corrupt    = 11,
	Not_Found  = 12,
	Full       = 13,
	Cant_Open  = 14,
	Protocol   = 15,
	Empty      = 16,
	Schema     = 17,
	Too_Big    = 18,
	Constraint = 19,
	Mismatch   = 20,
	Misuse     = 21,
	No_Lfs     = 22,
	Auth       = 23,
	Format     = 24,
	Range      = 25,
	Not_A_Db   = 26,
	Notice     = 27,
	Warning    = 28,
	// gap
	Row        = 100,
	Done       = 101,
}

// NOTE: functions with C calling conventions do not have access to the `context` variable.
Exec_Callback :: #type proc "c" (
	data: rawptr,
	argc: c.int,
	argv: [^]cstring,
	colnames: [^]cstring,
) -> c.int

Destructor :: #type proc "c" (_: rawptr)
Static: Destructor = nil
Transient: Destructor = transmute(Destructor)(rawptr(~uintptr(0)))

Column_Type :: enum c.int {
	Integer = 1,
	Float   = 2,
	Text    = 3,
	Blob    = 4,
	Null    = 5,
}

Open_Flag :: enum c.int {
	Readonly      = 0,
	Read_Write    = 1,
	Create        = 2,
	Uri           = 6,
	Memory        = 7,
	No_Mutex      = 15,
	Full_Mutex    = 16,
	Shared_Cache  = 17,
	Private_Cache = 18,
	No_Follow     = 24,
	Exrescode     = 25,
}

Open_Flags :: distinct bit_set[Open_Flag]

@(link_prefix = "sqlite3_")
foreign lib {
	libversion :: proc() -> cstring ---

	/*
		Returns 1 if the named compile-time option was defined, 0 otherwise.

		To get the compile-time options' names, see `compileoption_get`

		NOTE: this diagnostic itself may be compiled out, in which case it always
		returns 0.
	*/
	compileoption_used :: proc(opt_name: cstring) -> c.int ---

	/*
		Returns the N'th compile-time option string or nil when N is
		out of range.

		Call for `n=0` until it returns a nil value to enumerate available
		compile-time options.

		NOTE: values are owned by sqlite3, do *not* free.

		NOTE: this diagnostic itself may be compiled out, in which case it
		always returns nil
	*/
	compileoption_get :: proc(n: c.int) -> cstring ---


	/*
		Close sqlite3 database connection.

		NOTE: before calling, be sure to have cleaned up all resources (prepared statements, blob handlers, backup objects)
	*/
	close :: proc(db: sqlite3) -> Result_Code ---
	open :: proc(filename: cstring, db: ^sqlite3) -> Result_Code ---
	/*
		Open sqlite3 database connection.

		Flags must be any of EXACTLY
		{ .Readonly }
		{ .Read_Write }
		{ .Read_Write, .Create}

		... and optionally any of the other flags
		{
			.Uri, .Memory,
			.No_Mutex, .Full_Mutex,
			.Shared_Cache, .Private_Cache,
			.No_Follow,
			.Exrescode
		}

		Note that some flags are opposites. Expect a Result_Code of .Misuse when
		mixing flags in a nonsensical manner.

		NOTE: when making an in-memory database ({.Memory, ...}) `filename` MAY be nil - it may also be a name which affects .Shared_Cache behavior.

		NOTE: no support for `vfs` - so always pass nil to use the platform default
	*/
	open_v2 :: proc(filename: cstring, db: ^sqlite3, flags: Open_Flags, z_vfs: cstring) -> Result_Code ---

	/*
		Defines how many ms to wait (at least) for a table to no longer
		be locked before a query function like `step` returns .Busy

		NOTE: if `ms` is negative, the busy handler routine (if assigned) is cleared
	*/
	busy_timeout :: proc(db: sqlite3, ms: c.int) -> Result_Code ---

	/*
		Free memory dynamically acquired by sqlite3's `malloc` routine.
		Passing a nil pointer is harmless (NO-OP).
	*/
	free :: proc(_: rawptr) ---

	// NOTE: memory is internally managed, value may be overwritten. Create a copy of the string before issuing the next query if you wish to keep it.
	errmsg :: proc(db: sqlite3) -> cstring ---

	// NOTE: if errmsg is non-nil, you *must* free its memory after use
	/*
		If an error occurs AND `errmsg` is non-nil, the error message is written into memory obtained by sqlite3_malloc and the address is written to `errmsg`. BE SURE TO CALL sqlite3_free ON `errmsg` AFTER USE
	*/
	exec :: proc(db: sqlite3, sql: cstring, cb: Exec_Callback, cb_data: rawptr, errmsg: ^cstring) -> Result_Code ---

	// * stmt contains the compiled statement, may NOT be null
	// sql *could* be a string containing multiple SQL statements separated by ';'.
	// IF so, setting 'sqllen' to the full length of the string, then 'nxt_sql_stmt'
	// will point into 'sql' at the start of the next SQL statement.
	//
	// IF you haven't packed your SQL statements like this, you can just pass
	// prepare_v2(db, sql, -1, &stmt, nil)
	//
	// In this case, prepare assumes the SQL statement spans up to the first NULL
	// and returns no pointer to the next SQL statement
	prepare_v2 :: proc(db: sqlite3, sql: cstring, sqllen: c.int, stmt: ^Stmt, nxt_sql_stmt: ^cstring) -> Result_Code ---

	step :: proc(stmt: Stmt) -> Result_Code ---

	// Reset state - ready prepared statement for execution
	// NOTE: to actually clear the bindings, use clear_bindings
	// Return value indicates the result of the most recent evaluation of the statement
	reset :: proc(stmt: Stmt) -> Result_Code ---

	// Reset all variable bindings on prepared statement
	clear_bindings :: proc(stmt: Stmt) -> Result_Code ---

	// NOTE: returns the result of the most recent evaluation of the statement
	// NOTE: be sure to finalize all prepared statements before closing the connection
	finalize :: proc(stmt: Stmt) -> Result_Code ---

	bind_double :: proc(stmt: Stmt, pos: c.int, val: c.double) -> Result_Code ---
	bind_int :: proc(stmt: Stmt, pos: c.int, val: c.int) -> Result_Code ---
	bind_int64 :: proc(stmt: Stmt, pos: c.int, val: c.int64_t) -> Result_Code ---
	bind_null :: proc(stmt: Stmt, pos: c.int) -> Result_Code ---
	// NOTE: `n` can be the string length, if '-1', assumed read to first NULL
	bind_text :: proc(stmt: Stmt, pos: c.int, val: cstring, n: c.int, dtor: Destructor) -> Result_Code ---
	// NOTE: `n` must be a non-negative number
	bind_blob :: proc(stmt: Stmt, pos: c.int, data: rawptr, n: c.int, dtor: Destructor) -> Result_Code ---


	// Return number of columns returned in result set
	column_count :: proc(stmt: Stmt) -> c.int ---

	// Return data type of values in the given column
	column_type :: proc(stmt: Stmt, col_ndx: c.int) -> Column_Type ---

	column_int :: proc(stmt: Stmt, col_ndx: c.int) -> c.int ---
	column_int64 :: proc(stmt: Stmt, col_ndx: c.int) -> c.int64_t ---
	column_double :: proc(stmt: Stmt, col_ndx: c.int) -> c.double ---
	// NOTE: use column_bytes to query its length
	// NOTE: returned value is valid only during this step (until next step/reset/finalize)
	column_text :: proc(stmt: Stmt, col_ndx: c.int) -> cstring ---
	// NOTE: use column_bytes to query its length
	// NOTE: returned value is valid only during this step (until next step/reset/finalize)
	column_blob :: proc(stmt: Stmt, col_ndx: c.int) -> rawptr ---

	// byte length of value (use for Text and Blob values)
	column_bytes :: proc(stmt: Stmt, col_ndx: c.int) -> c.int ---

	/*
		Return column name.

		Valid until either event:
		- next call to `column_name`
		- statement is finalized
		- first call to `step` in a run (e.g. after having called `reset`)
	*/
	column_name :: proc(stmt: Stmt, col_ndx: c.int) -> cstring ---


	// ROWID of most recent successful insert on connection.
	// Called after an insert to obtain the ID of the newly inserted row when using AUTOINCREMENT
	last_insert_rowid :: proc(db: sqlite3) -> c.int64_t ---

	// return number of rows affected by most recently completed INSERT/UPDATE/DELETE
	changes64 :: proc(db: sqlite3) -> c.int64_t ---
}
