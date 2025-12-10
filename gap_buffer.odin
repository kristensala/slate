package main

import "core:fmt"

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

grow_gap :: proc(line: ^Gap_Buffer, cursor_pos: i32) {
    new_data := make([]rune, line.cap + DEFAULT_GAP_BUFFER_SIZE - 1)
    gap_end := cursor_pos + DEFAULT_GAP_BUFFER_SIZE

    // before cursor
    for char, idx in line.data[:cursor_pos] {
        new_data[idx] = char
    }

    // after cursor
    for char, idx in line.data[cursor_pos + 1:] {
        i := cursor_pos + DEFAULT_GAP_BUFFER_SIZE + i32(idx)
        new_data[i] = char
    }

    line.data = new_data
    line.gap_start = cursor_pos
    line.gap_end = gap_end
    line.cap = i32(len(new_data))
    line.gap_size = gap_end - cursor_pos
}

// cursor pos will be the start of the gap
// end of the cap = cursor_pos + gap_size
move_gap :: proc(line: ^Gap_Buffer, cursor_pos: i32) {

}

