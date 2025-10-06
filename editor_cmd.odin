package main

import "core:fmt"
import "core:strings"
import sdl "vendor:sdl3"

Command_Line :: struct {
    cursor: ^Cursor,
    input: ^[dynamic]Character_Info,
    pos: [2]i32 // where the text is displayed
}

editor_command_line_on_text_input :: proc(editor: ^Editor, char: int) {
    glyph := get_glyph_from_atlas(editor.glyph_atlas, char)
    if glyph == nil {
        fmt.eprintln("Glyph not found from atlas: ", char)
        return
    }

    editor.cmd_line.cursor.x += glyph.advance

    character_info := Character_Info{
        char = rune(char),
        glyph = glyph
    }

    append_char_at(editor.cmd_line.input, character_info, editor.cmd_line.cursor.col_index)
    editor.cmd_line.cursor.col_index += 1
}

editor_cmd_line_on_backspace :: proc(e: ^Editor) {
    if e.cmd_line.cursor.col_index == 0 {
        return
    }

    e.cmd_line.cursor.col_index -= 1
    glyph_under_cursor := e.cmd_line.input[e.cmd_line.cursor.col_index].glyph
    if glyph_under_cursor == nil {
        fmt.eprintln("Could not get glyph under the cursor")
        e.cmd_line.cursor.col_index += 1
        return
    }

    e.cmd_line.cursor.x -= glyph_under_cursor.advance
    ordered_remove(e.cmd_line.input, e.cmd_line.cursor.col_index)
}


editor_cmd_line_on_return :: proc(e: ^Editor) {
}

editor_command_line_draw_text :: proc(e: ^Editor, pos_y: i32) {
    pen_x : i32

    sdl.SetTextureColorMod(
        e.glyph_atlas.texture,
        e.theme.text_color.r,
        e.theme.text_color.g,
        e.theme.text_color.b)

    for char_info in e.cmd_line.input {
        glyph := char_info.glyph

        glyph_x := pen_x
        glyph_y := pos_y
        destination : sdl.FRect = {f32(glyph_x), f32(glyph_y), f32(glyph.width), f32(glyph.height)}

        uv : sdl.FRect
        sdl.RectToFRect(glyph.uv, &uv)

        sdl.RenderTexture(e.renderer, e.glyph_atlas.texture, &uv, &destination)
        pen_x += glyph.advance
    }

}

reset_cmd_line :: proc(e: ^Editor) {
    e.cmd_line.cursor.x = 0
    e.cmd_line.cursor.col_index = 0
    clear(e.cmd_line.input)
}

