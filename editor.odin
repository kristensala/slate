package main

import "core:fmt"
import "core:strings"
import sdl "vendor:sdl2"
import ttf "vendor:sdl2/ttf"

@(private) EDITOR_FONT_SIZE :: 30
EDITOR_GUTTER_OFFSET_X :: 10
EDITOR_OFFSET_X :: EDITOR_GUTTER_OFFSET_X + 50

Vim_Mode :: enum {
    Normal,
    Visual,
    Insert
}

Editor :: struct {
    renderer: ^sdl.Renderer,
    font: ^ttf.Font,
    glyph_atlas: ^Atlas,
    lines: [dynamic]Line,
    cursor: Cursor,
    line_height: i32,
    vim_mode_enabled: bool,
    vim_mode: Vim_Mode
}

Line :: struct {
    chars: [dynamic]rune,
    x, y: i32,
}

Cursor :: struct {
    line_index: i32,
    col_index: i32,
    x, y: i32 // pixel pos
}

editor_draw_text :: proc(editor: ^Editor) {
    pen_x : i32 = EDITOR_OFFSET_X
    baseline : i32 = 0

    for line, i in editor.lines {
        for character in line.chars {
            code_point := int(character)
            glyph := get_glyph_from_atlas(editor.glyph_atlas, code_point)

            if glyph == nil {
                continue
            }

            glyph_x := pen_x + glyph.bearing_x
            glyph_y := baseline //- glyph.bearing_y
            destination : sdl.Rect = {glyph_x, glyph_y, glyph.width, glyph.height}

            sdl.RenderCopy(editor.renderer, editor.glyph_atlas.texture, &glyph.uv, &destination)
            pen_x += glyph.advance;
        }

        editor_draw_line_nr(editor, i + 1, {EDITOR_GUTTER_OFFSET_X, baseline})

        baseline += editor.glyph_atlas.font_line_skip
        pen_x = EDITOR_OFFSET_X
    }
}

editor_move_cursor_up :: proc(editor: ^Editor) {
    if editor.cursor.line_index == 0 {
        return
    }

    editor.cursor.line_index -= 1
    editor.cursor.col_index = 0
    editor.cursor.y -= editor.line_height
    editor.cursor.x = EDITOR_OFFSET_X
}

editor_move_cursor_down :: proc(editor: ^Editor) {
    if int(editor.cursor.line_index + 1) == len(editor.lines) {
        return
    }
    editor.cursor.line_index += 1
    editor.cursor.col_index =0
    editor.cursor.y += editor.line_height
    editor.cursor.x = EDITOR_OFFSET_X
}

editor_move_cursor_left :: proc(editor: ^Editor) {
    if editor.cursor.col_index == 0 {
        return
    }

    editor.cursor.col_index -= 1
    glyph := get_glyph_by_cursor_pos(editor, editor.cursor.line_index, editor.cursor.col_index)
    editor.cursor.x -= glyph.advance
}

editor_move_cursor_right :: proc(editor: ^Editor) {
    line := editor.lines[editor.cursor.line_index]
    char_count := i32(len(line.chars))

    if editor.cursor.col_index >= char_count {
        return
    }

    glyph := get_glyph_from_atlas(editor.glyph_atlas, int(line.chars[editor.cursor.col_index]))
    editor.cursor.x += glyph.advance
    editor.cursor.col_index += 1
}

editor_on_backspace :: proc(editor: ^Editor) {
    if editor.cursor.col_index == 0 {
        if editor.cursor.line_index == 0 {
            return
        }

        // @todo: move to the previous line
        return
    }

    editor.cursor.col_index -= 1
    glyph_to_remove := get_glyph_by_cursor_pos(editor, editor.cursor.line_index, editor.cursor.col_index)

    line := &editor.lines[editor.cursor.line_index]
    ordered_remove(&line.chars, editor.cursor.col_index)
    editor.cursor.x -= glyph_to_remove.advance
}

// @todo: move text right from the cursor to the new line
editor_on_return :: proc(editor: ^Editor) {
    editor.cursor.line_index += 1
    editor.cursor.y += editor.line_height

    // @todo: cursor col needs to stay the same if possible,
    // otherwise should be at the end of the line
    editor.cursor.col_index = 0
    editor.cursor.x = EDITOR_OFFSET_X

    line_chars : [dynamic]rune
    append_line_at(&editor.lines, Line{
        x = 0,
        y = editor.cursor.line_index,
        chars = line_chars
    }, editor.cursor.line_index)
}

editor_on_text_input :: proc(editor: ^Editor, char: int) {
    glyph := get_glyph_from_atlas(editor.glyph_atlas, char)
    editor.cursor.x += glyph.advance

    character := rune(char)
    line := &editor.lines[editor.cursor.line_index]
    append_char_at(&line.chars, character, editor.cursor.col_index)
    editor.cursor.col_index += 1
}

editor_draw_rect :: proc(renderer: ^sdl.Renderer, color: sdl.Color, pos: [2]i32, w: i32, h: i32) {
    sdl.SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a)
    rect: sdl.Rect = {pos.x, pos.y, w, h};
    sdl.RenderFillRect(renderer, &rect)
}

@(private = "file")
editor_draw_line_nr :: proc(editor: ^Editor, line_nr: int, pos: [2]i32) {
    line_nr := fmt.tprintf("%v", line_nr)
    line_nr_cstring := strings.clone_to_cstring(line_nr)
    defer delete(line_nr_cstring)

    surface := ttf.RenderUTF8_Blended(editor.font, line_nr_cstring, {255, 255, 255, 50})
    defer sdl.FreeSurface(surface)

    tex := sdl.CreateTextureFromSurface(editor.renderer, surface)
    defer sdl.DestroyTexture(tex)

    rect : sdl.Rect = {pos.x, pos.y, surface.w, surface.h}
    sdl.RenderCopy(editor.renderer, tex, nil, &rect)
}

@(private = "file")
get_glyph_by_cursor_pos :: proc(editor: ^Editor, line: i32, col: i32) -> ^Glyph {
    line := &editor.lines[line]
    glyph := get_glyph_from_atlas(editor.glyph_atlas, int(line.chars[col]))
    return glyph
}


