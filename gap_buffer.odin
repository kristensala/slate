package main

import "core:fmt"

// @note(ksala): for testing purpose keep the buffer size small.
// After testing, each line buffer should be around 32 at least
DEFAULT_GAP_BUFFER_SIZE :: 10

Gap_Buffer :: struct {
    data: []rune,

    // Max capacity, len + GAP_BUFFER_SIZE
    // if len == cap or gap_end - gap_start == 0; then grow the gap 
    cap: i32, 
    // The length of the actual string
    // Can be calculated: len(data) - (gap_end - gap_start)
    len: i32,

    gap_start: i32,
    gap_end: i32,
    gap_size: i32 // @todo: do I have to keep track of this?
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

