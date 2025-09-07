package main

append_line_at :: proc(editor_lines: ^[dynamic]Line, line: Line, index: i32) {
    result : [dynamic]Line
    first_part := editor_lines[0 : index]
    last_part := editor_lines[index:]

    append(&result, ..first_part[:])
    append(&result, line)
    append(&result, ..last_part[:])

    editor_lines^ = result
}
