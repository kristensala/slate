package main

import sdl "vendor:sdl3"

append_line_at :: proc(editor_lines: ^[dynamic]Line, line: Line, index: i32) {
    result : [dynamic]Line
    first_part := editor_lines[0 : index]
    last_part := editor_lines[index:]

    append(&result, ..first_part[:])
    append(&result, line)
    append(&result, ..last_part[:])

    editor_lines^ = result
}

append_char_at :: proc(chars: ^[dynamic]Character_Info, char: Character_Info, index: i32) {
    result : [dynamic]Character_Info
    first_part := chars[0 : index]
    last_part := chars[index:]

    append(&result, ..first_part[:])
    append(&result, char)
    append(&result, ..last_part[:])

    chars^ = result
}

