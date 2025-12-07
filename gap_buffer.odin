package main

DEFAULT_GAP_BUFFER_SIZE :: 10

Gap_Buffer :: struct {
    data: []rune,

    // if len == cap then grow the gap
    cap: i32, // Max capacity, len + GAP_BUFFER_SIZE
    len: i32, // The length of the actual string

    gap_start: i32,
    gap_end: i32,
    gap_size: i32
}

// have to grow from the current cursor position
grow_gap :: proc(line: ^Gap_Buffer, cursor_pos: i32) {
    new_data := make([]rune, line.cap + DEFAULT_GAP_BUFFER_SIZE)

    //free(line)
}

// cursor pos will be the start of the gap
// end of the cap = cursor_pos + gap_size
move_gap :: proc(line: ^Gap_Buffer, cursor_pos: i32) {

}

