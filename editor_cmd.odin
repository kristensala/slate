package main

import "core:fmt"
import "core:strings"
import "core:strconv"
import sdl "vendor:sdl3"

Command_Line :: struct {
    cursor: ^Cursor,
    input: ^[dynamic]rune,
    pos: [2]i32 // where the text is displayed
}

editor_command_line_on_text_input :: proc(editor: ^Editor, char: int) {
    glyph := get_glyph_from_atlas(editor.glyph_atlas, char)
    if glyph == nil {
        fmt.eprintln("Glyph not found from atlas: ", char)
        return
    }

    editor.cmd_line.cursor.x += glyph.advance

    append_char_at(editor.cmd_line.input, rune(char), editor.cmd_line.cursor.col_index)
    editor.cmd_line.cursor.col_index += 1
}

editor_cmd_line_on_backspace :: proc(e: ^Editor) {
    if e.cmd_line.cursor.col_index == 0 {
        return
    }

    e.cmd_line.cursor.col_index -= 1
    char := e.cmd_line.input[e.cmd_line.cursor.col_index]
    glyph := get_glyph_from_atlas(e.glyph_atlas, int(char))
    if glyph == nil {
        fmt.eprintln("Could not get glyph under the cursor")
        e.cmd_line.cursor.col_index += 1
        return
    }

    e.cmd_line.cursor.x -= glyph.advance
    ordered_remove(e.cmd_line.input, e.cmd_line.cursor.col_index)
}

// @todo
editor_cmd_line_on_return :: proc(e: ^Editor) {
    input := e.cmd_line.input
    if len(input) == 0 {
        return
    }

    if input[0] == ':' {
        if len(input) == 1 {
            return
        }
        leading := input[1:]
        if len(leading) == 1 && leading[0] == 'q' {
            editor_quit()
            return
        }

        builder := strings.builder_make()
        defer strings.builder_destroy(&builder)

        for c in leading {
            strings.write_rune(&builder, c)
        }

        str := strings.to_string(builder)
        int_value, ok := strconv.parse_int(str)
        if ok {
            editor_move_cursor_to(e, i32(int_value - 1), 0)
            e.active_viewport = .EDITOR

            reset_cmd_line(e)
            return
        }
    }
}

editor_command_line_draw_text :: proc(e: ^Editor, pos_y: i32) {
    pen_x : i32

    sdl.SetTextureColorMod(
        e.glyph_atlas.texture,
        e.theme.text_color.r,
        e.theme.text_color.g,
        e.theme.text_color.b)

    for char in e.cmd_line.input {
        glyph := get_glyph_from_atlas(e.glyph_atlas, int(char))

        glyph_x := pen_x
        glyph_y := pos_y
        destination : sdl.FRect = {f32(glyph_x), f32(glyph_y), f32(glyph.width), f32(glyph.height)}

        uv : sdl.FRect
        sdl.RectToFRect(glyph.uv, &uv)

        sdl.RenderTexture(e.renderer, e.glyph_atlas.texture, &uv, &destination)
        pen_x += glyph.advance
    }

}

editor_quit :: proc() -> bool {
    quit_event := sdl.Event{
        type = .QUIT
    }
    ok := sdl.PushEvent(&quit_event)
    if !ok {
        fmt.eprintln("Failed to send sdl Quit event. ", sdl.GetError())
    }

    return ok
}

reset_cmd_line :: proc(e: ^Editor) {
    e.cmd_line.cursor.x = 0
    e.cmd_line.cursor.col_index = 0
    clear(e.cmd_line.input)
}

