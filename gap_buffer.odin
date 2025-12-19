package main

import "core:fmt"

/*
    @todo: how does the gap buffer work when moving
    between the lines(enter, backspace, arrow keys)? - 12.12.25
*/

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

// @todo: I should not move the gap on cursor move.
// Insted move it when I start editing the text
move_gap :: proc(
    line: ^Gap_Buffer,
    cursor_pos: i32,
    move_direction: Cursor_Move_Direction
) {
    gap_size := line.gap_end - line.gap_start
    if gap_size <= 0 {
        return
    }

    if move_direction == .RIGHT {
        line.data[line.gap_start] = line.data[line.gap_end]
        line.gap_start = cursor_pos
        line.data[line.gap_end] = line.data[line.gap_start]
        line.gap_end = line.gap_start + gap_size
        return
    }

    if move_direction == .LEFT {
        last_char := line.data[line.gap_end - 1]
        line.data[line.gap_end - 1] = line.data[cursor_pos]
        line.gap_start = cursor_pos
        line.data[line.gap_start] = last_char
        line.gap_end = line.gap_start + gap_size
        return
    }
}
