package main

import sdl "vendor:sdl2"

append_line_at :: proc(editor_lines: ^[dynamic]Line, line: Line, index: i32) {
    result : [dynamic]Line
    first_part := editor_lines[0 : index]
    last_part := editor_lines[index:]

    append(&result, ..first_part[:])
    append(&result, line)
    append(&result, ..last_part[:])

    editor_lines^ = result
}

append_char_at :: proc(chars: ^[dynamic]rune, char: rune, index: i32) {
    result : [dynamic]rune
    first_part := chars[0 : index]
    last_part := chars[index:]

    append(&result, ..first_part[:])
    append(&result, char)
    append(&result, ..last_part[:])

    chars^ = result
}

draw_rect :: proc(renderer: ^sdl.Renderer, color: sdl.Color, pos: [2]i32, w: i32, h: i32) {
    sdl.SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a)
    rect: sdl.Rect = {pos.x, pos.y, w, h};
    sdl.RenderFillRect(renderer, &rect)
}
