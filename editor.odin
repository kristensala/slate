package main

import "core:fmt"
import "core:os"
import "core:strings"
import sdl "vendor:sdl2"
import ttf "vendor:sdl2/ttf"

@(private) EDITOR_FONT_SIZE :: 20
EDITOR_GUTTER_OFFSET_X :: 10
EDITOR_OFFSET_X :: EDITOR_GUTTER_OFFSET_X + 50
EDITOR_CURSOR_OFFSET :: 8 // 8 lines

Vim_Mode :: enum {
    Normal,
    Visual,
    Insert
}

Editor :: struct {
    text_input_rect: sdl.Rect,
    renderer: ^sdl.Renderer,
    font: ^ttf.Font,
    glyph_atlas: ^Atlas,
    lines: [dynamic]Line,
    lines_start: i32,
    lines_end: i32,
    cursor: Cursor,
    line_height: i32,
    vim_mode_enabled: bool,
    vim_mode: Vim_Mode
}

Line :: struct {
    chars: [dynamic]Character_Info,
    x, y: i32,
}

Character_Info :: struct {
    char: rune,
    glyph: ^Glyph // @fix: does this have to be a pointer?
}

Cursor :: struct {
    line_index: i32,
    col_index: i32,
    x, y: i32 // pixel pos
}

Cursor_Move_Direction :: enum {
    NONE,
    UP,
    DOWN
}

editor_draw_text :: proc(editor: ^Editor) {
    pen_x : i32 = EDITOR_OFFSET_X
    baseline : i32 = 0

    for line, i in editor.lines {
        if i32(i) < editor.lines_start || i32(i) > editor.lines_end {
            continue
        }
        for character_info in line.chars {
            glyph := character_info.glyph
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

// @todo: keep cursor column same if possible
editor_move_cursor_up :: proc(editor: ^Editor, override_col := false, window: ^sdl.Window) {
    if editor.cursor.line_index == 0 {
        return
    }
    editor.cursor.line_index -= 1
    editor_set_visible_lines(editor, window, .UP)

    cursor_idx_in_view := get_cursor_index_in_visible_lines(editor^)
    editor.cursor.y = cursor_idx_in_view * editor.line_height


    // @hack: if I want to move the cursor up,
    // but want to calculate the cursor x (horizontal) pos separately
    if !override_col {
        editor.cursor.col_index = 0
        editor.cursor.x = EDITOR_OFFSET_X
    }
}

// @todo: keep cursor column same if possible
editor_move_cursor_down :: proc(editor: ^Editor, window: ^sdl.Window) {
    if int(editor.cursor.line_index + 1) == len(editor.lines) {
        return
    }

    editor.cursor.line_index += 1
    editor.cursor.col_index = 0
    editor_set_visible_lines(editor, window, .DOWN)

    cursor_idx_in_view := get_cursor_index_in_visible_lines(editor^)
    editor.cursor.y = cursor_idx_in_view * editor.line_height

    // if cursor pos is on the last line do not add y
    editor.cursor.x = EDITOR_OFFSET_X
}

editor_move_cursor_left :: proc(editor: ^Editor) {
    if editor.cursor.col_index == 0 {
        return
    }

    editor.cursor.col_index -= 1
    glyph := get_glyph_by_cursor_pos(editor)
    editor.cursor.x -= glyph.advance
}

editor_move_cursor_right :: proc(editor: ^Editor) {
    line := editor.lines[editor.cursor.line_index]
    char_count := i32(len(line.chars))

    if editor.cursor.col_index >= char_count {
        return
    }

    glyph := line.chars[editor.cursor.col_index].glyph
    editor.cursor.x += glyph.advance
    editor.cursor.col_index += 1
}

editor_on_backspace :: proc(editor: ^Editor, window: ^sdl.Window) {
    if editor.cursor.col_index == 0 {
        if editor.cursor.line_index == 0 {
            return
        }

        current_line := editor.lines[editor.cursor.line_index]
        line_above_current_line := &editor.lines[editor.cursor.line_index - 1]

        editor.cursor.col_index = i32(len(line_above_current_line.chars))
        editor.cursor.x = EDITOR_OFFSET_X
        for c in line_above_current_line.chars {
            editor.cursor.x += c.glyph.advance
        }

        if len(current_line.chars) > 0 {
            append(&line_above_current_line.chars, ..current_line.chars[:])
        }

        ordered_remove(&editor.lines, editor.cursor.line_index)
        editor_move_cursor_up(editor, true, window)
        return
    }

    editor.cursor.col_index -= 1
    glyph_to_remove := get_glyph_by_cursor_pos(editor)

    line := &editor.lines[editor.cursor.line_index]
    ordered_remove(&line.chars, editor.cursor.col_index)
    editor.cursor.x -= glyph_to_remove.advance
}

editor_on_return :: proc(editor: ^Editor, window: ^sdl.Window) {
    current_line := &editor.lines[editor.cursor.line_index]
    current_col := editor.cursor.col_index
    chars_to_move: []Character_Info
    defer {
        chars_to_move = nil
    }

    if current_col == 0 {
        chars_to_move = current_line.chars[current_col:]
        clear(&current_line.chars)
    }

    if current_col > 0 {
        data: [dynamic]Character_Info
        chars_to_move = current_line.chars[current_col:]
        chars_to_keep := current_line.chars[:current_col]
        append(&data, ..chars_to_keep[:])
        current_line.chars = data
    }

    editor.cursor.line_index += 1

    editor.cursor.col_index = 0
    editor.cursor.x = EDITOR_OFFSET_X

    editor_set_visible_lines(editor, window, .DOWN)

    cursor_pos_idx_in_view := get_cursor_index_in_visible_lines(editor^)
    editor.cursor.y = cursor_pos_idx_in_view * editor.line_height

    line_chars : [dynamic]Character_Info
    if len(chars_to_move) > 0 {
        append(&line_chars, ..chars_to_move[:])
    }


    append_line_at(&editor.lines, Line{
        x = 0,
        y = editor.cursor.line_index,
        chars = line_chars
    }, editor.cursor.line_index)
}

editor_on_tab :: proc(editor: ^Editor) {
    for _ in 0..<4 {
        editor_on_text_input(editor, 32) // 32 is space
    }
}

editor_on_text_input :: proc(editor: ^Editor, char: int) {
    glyph := get_glyph_from_atlas(editor.glyph_atlas, char)
    editor.cursor.x += glyph.advance

    character_info := Character_Info{
        char = rune(char),
        glyph = glyph
    }
    line := &editor.lines[editor.cursor.line_index]
    append_char_at(&line.chars, character_info, editor.cursor.col_index)
    editor.cursor.col_index += 1
}

editor_on_command :: proc() {
}

editor_draw_rect :: proc(renderer: ^sdl.Renderer, color: sdl.Color, pos: [2]i32, w: i32, h: i32) {
    sdl.SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a)
    rect: sdl.Rect = {pos.x, pos.y, w, h};
    sdl.RenderFillRect(renderer, &rect)
}

editor_on_file_open :: proc(editor: ^Editor, file_name: string) {
    data, ok := os.read_entire_file_from_filename(file_name)
    if !ok {
        fmt.eprintln("Could not read the file")
        return
    }
    defer delete(data)

    it := string(data)
    lines: [dynamic]Line
    for line in strings.split_lines_iterator(&it) {
        editor_line := Line{
            chars = make([dynamic]Character_Info)
        }
        for character in line {
            cp := int(character)
            glyph := get_glyph_from_atlas(editor.glyph_atlas, cp)

            character_info := Character_Info{
                char = character,
                glyph = glyph
            }
            append(&editor_line.chars, character_info)
        }

        append(&lines, editor_line)
    }

    clear(&editor.lines)
    append(&editor.lines, ..lines[:])
}

@(private = "file")
editor_get_visible_lines :: proc(editor: ^Editor) {
    // @todo: get visible lines and only draw them
    // window height / editor.line_height = max_visible_lines
    // how to get the start and end lines?
    // cursor pos > max_visible_lines then start++ and end = start + max_visible_lines
}

// @fix: also use an atlas for this
// line_nr should be a rune then ex: "1"
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
get_glyph_by_cursor_pos :: proc(editor: ^Editor) -> ^Glyph {
    line := editor.lines[editor.cursor.line_index]
    glyph := line.chars[editor.cursor.col_index].glyph
    return glyph
}

@(private = "file")
get_normalized_window_height :: proc(window: ^sdl.Window, editor_line_height: i32) -> i32 {
    w, h: i32
    sdl.GetWindowSize(window, &w, &h)

    lines_count := h / editor_line_height
    normalized_height := lines_count * editor_line_height
    return normalized_height
}

@(private = "file")
get_cursor_index_in_visible_lines :: proc(editor: Editor) -> i32 {
    cursor_row_nr := editor.cursor.line_index
    cursor_idx_in_visible_lines := cursor_row_nr - editor.lines_start
    return cursor_idx_in_visible_lines
}

editor_set_visible_lines :: proc(editor: ^Editor, window: ^sdl.Window, move_dir: Cursor_Move_Direction = .NONE) {
    w, h: i32
    sdl.GetWindowSize(window, &w, &h)

    max_visible_rows := h / editor.line_height

    cursor_idx_in_visible_lines := get_cursor_index_in_visible_lines(editor^)
    if cursor_idx_in_visible_lines >= max_visible_rows && move_dir == .DOWN {
        editor.lines_start = editor.cursor.line_index + 1 - max_visible_rows
    }

    if editor.cursor.line_index < editor.lines_start {
        editor.lines_start = editor.cursor.line_index
    }
    editor.lines_end = editor.lines_start + max_visible_rows
}

