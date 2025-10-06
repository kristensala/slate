package main

import "core:fmt"
import "core:strings"

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

    if editor.cursor.x + glyph.advance > editor.cursor_right_side_cutoff_line {
        editor.editor_offset_x -= glyph.advance
    } else {
        editor.cursor.x += glyph.advance
    }

    character_info := Character_Info{
        char = rune(char),
        glyph = glyph
    }

    append_char_at(editor.cmd_line.input, character_info, editor.cmd_line.cursor.col_index)
    editor.cmd_line.cursor.col_index += 1

    //fmt.println(editor.cmd_line.input)
}

editor_command_line_draw_text :: proc(e: ^Editor) {
}

