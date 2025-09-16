package main

import "core:fmt"
import "core:os"
import "core:strings"
import sdl "vendor:sdl2"
import ttf "vendor:sdl2/ttf"

EDITOR_FONT_SIZE :: 25
EDITOR_GUTTER_WIDTH :: 70
DEFAULT_EDITOR_OFFSET_X :: EDITOR_GUTTER_WIDTH + 10
//EDITOR_CURSOR_OFFSET :: 8 // 8 lines

COMMAND_LINE_HEIGHT :: 25

Cursor_Move_Event :: enum {
    ARROW_KEYS,
    BACKSPACE
}

Vim_Mode :: enum {
    NORMAL,
    VISUAL,
    INSERT
}

Viewport :: enum {
    EDITOR,
    COMMAND_LINE
}

Editor :: struct {
    editor_gutter_clip: sdl.Rect,
    editor_clip: sdl.Rect,
    editor_offset_x: i32, // to track horizontal scrolling
    command_clip: sdl.Rect,
    active_viewport: Viewport,

    renderer: ^sdl.Renderer,
    font: ^ttf.Font,
    glyph_atlas: ^Atlas,

    lines: ^[dynamic]Line,
    lines_start: i32,
    lines_end: i32,
    line_height: i32,

    cursor: Cursor,

    vim_mode_enabled: bool,
    vim_mode: Vim_Mode
}

Line :: struct {
    chars: [dynamic]Character_Info,
    x, y: i32,
}

Character_Info :: struct {
    char: rune,
    glyph: ^Glyph
}

Cursor :: struct {
    line_index: i32,
    col_index: i32, // current col index

    // update every time cursor is moved manually left or right
    memorized_col_index: i32,
    x, y: i32 // pixel pos
}

Cursor_Move_Direction :: enum {
    NONE,
    UP,
    DOWN
}

editor_draw_text :: proc(editor: ^Editor) {
    pen_x : i32 = editor.editor_offset_x
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

        baseline += editor.glyph_atlas.font_line_skip
        pen_x = editor.editor_offset_x
    }
}

editor_move_cursor_up :: proc(editor: ^Editor, window: ^sdl.Window, event: Cursor_Move_Event) {
    if editor.cursor.line_index == 0 {
        return
    }

    editor.cursor.line_index -= 1
    editor_set_visible_lines(editor, window, .UP)

    cursor_idx_in_view := get_cursor_index_in_visible_lines(editor^)
    editor.cursor.y = cursor_idx_in_view * editor.line_height

    if editor.editor_clip.w >= editor_get_current_line_width(editor) {
        editor.editor_offset_x = DEFAULT_EDITOR_OFFSET_X
    }

    if event == .ARROW_KEYS {
        retain_cursor_column(editor)
    }
}

// @todo: keep cursor column same if possible
editor_move_cursor_down :: proc(editor: ^Editor, window: ^sdl.Window) {
    if int(editor.cursor.line_index + 1) == len(editor.lines) {
        return
    }

    // @temp
    //editor.editor_offset_x = DEFAULT_EDITOR_OFFSET_X

    editor.cursor.line_index += 1
    editor_set_visible_lines(editor, window, .DOWN)

    cursor_idx_in_view := get_cursor_index_in_visible_lines(editor^)
    editor.cursor.y = cursor_idx_in_view * editor.line_height

    retain_cursor_column(editor)
}

editor_move_cursor_left :: proc(editor: ^Editor) {
    if editor.cursor.col_index <= 0 {
        editor.cursor.col_index = 0 // failsafe
        editor.editor_offset_x = DEFAULT_EDITOR_OFFSET_X
        return
    }

    editor.cursor.col_index -= 1
    glyph := get_glyph_by_cursor_pos(editor)

    calculated_cursor_pos := calculate_cursor_pos_on_line(editor)
    if calculated_cursor_pos < DEFAULT_EDITOR_OFFSET_X {
        editor.editor_offset_x += glyph.advance
        editor.cursor.x = DEFAULT_EDITOR_OFFSET_X
    } else {
        editor.cursor.x = calculated_cursor_pos
    }

    if editor.cursor.col_index == 0 {
        editor.editor_offset_x = DEFAULT_EDITOR_OFFSET_X
    }

    assert(editor.cursor.x >= DEFAULT_EDITOR_OFFSET_X)

    editor.cursor.memorized_col_index = editor.cursor.col_index
}

editor_move_cursor_right :: proc(editor: ^Editor, window: ^sdl.Window) {
    line := editor.lines[editor.cursor.line_index]
    char_count := i32(len(line.chars))
    if char_count == 0 || char_count == editor.cursor.col_index {
        return
    }

    w, h : i32
    sdl.GetWindowSize(window, &w, &h)

    glyph := line.chars[editor.cursor.col_index].glyph
    editor.cursor.col_index += 1
    calculated_cursor_pos := calculate_cursor_pos_on_line(editor)

    if calculated_cursor_pos > w {
        editor.editor_offset_x -= glyph.advance
        editor.cursor.x = w
    } else {
        editor.cursor.x = calculated_cursor_pos
    }

    assert(editor.cursor.x <= w, "Cursor is off the screen, right side")

    editor.cursor.memorized_col_index = editor.cursor.col_index
}

editor_on_backspace :: proc(editor: ^Editor, window: ^sdl.Window) {
    if editor.cursor.col_index == 0 {
        if editor.cursor.line_index == 0 {
            return
        }

        current_line := editor.lines[editor.cursor.line_index]
        line_above_current_line := &editor.lines[editor.cursor.line_index - 1]

        editor.cursor.col_index = i32(len(line_above_current_line.chars))
        editor.cursor.memorized_col_index = editor.cursor.col_index

        for c in line_above_current_line.chars {
            editor.cursor.x += c.glyph.advance
        }

        if len(current_line.chars) > 0 {
            append(&line_above_current_line.chars, ..current_line.chars[:])
        }

        ordered_remove(editor.lines, editor.cursor.line_index)
        editor_move_cursor_up(editor, window, .BACKSPACE)
        return
    }

    editor_move_cursor_left(editor)
    editor.cursor.memorized_col_index = editor.cursor.col_index
    glyph_to_remove := get_glyph_by_cursor_pos(editor)

    line := &editor.lines[editor.cursor.line_index]
    ordered_remove(&line.chars, editor.cursor.col_index)
}

editor_on_return :: proc(editor: ^Editor, window: ^sdl.Window) {
    editor.editor_offset_x = DEFAULT_EDITOR_OFFSET_X

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
    editor.cursor.memorized_col_index = editor.cursor.col_index
    editor.cursor.x = editor.editor_offset_x

    editor_set_visible_lines(editor, window, .DOWN)

    cursor_pos_idx_in_view := get_cursor_index_in_visible_lines(editor^)
    editor.cursor.y = cursor_pos_idx_in_view * editor.line_height

    line_chars : [dynamic]Character_Info
    if len(chars_to_move) > 0 {
        append(&line_chars, ..chars_to_move[:])
    }


    append_line_at(editor.lines, Line{
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

    right_bound := editor.editor_clip.x + editor.editor_clip.w
    if editor.cursor.x + glyph.advance > right_bound {
        editor.editor_offset_x -= glyph.advance
    } else {
        editor.cursor.x += glyph.advance
    }

    character_info := Character_Info{
        char = rune(char),
        glyph = glyph
    }
    line := &editor.lines[editor.cursor.line_index]
    append_char_at(&line.chars, character_info, editor.cursor.col_index)

    editor.cursor.col_index += 1
    editor.cursor.memorized_col_index = editor.cursor.col_index
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

    clear(editor.lines)
    append(editor.lines, ..lines[:])
}

// @fix: also use an atlas for this
// line_nr should be a rune then ex: "1"
editor_draw_line_nr :: proc(editor: ^Editor) {
    line_skip: i32 = 0
    for i in editor.lines_start..<editor.lines_end {
        line_nr := fmt.tprintf("%v", i + 1)
        line_nr_cstring := strings.clone_to_cstring(line_nr)
        defer delete(line_nr_cstring)

        surface := ttf.RenderUTF8_Blended(editor.font, line_nr_cstring, {255, 255, 255, 50})
        defer sdl.FreeSurface(surface)

        tex := sdl.CreateTextureFromSurface(editor.renderer, surface)
        defer sdl.DestroyTexture(tex)

        rect : sdl.Rect = {0, line_skip, surface.w, surface.h}
        sdl.RenderCopy(editor.renderer, tex, nil, &rect)

        line_skip += editor.glyph_atlas.font_line_skip
    }
}

// @bug when the editor is offset
calculate_cursor_pos_on_line :: proc(editor: ^Editor) -> i32 {
    cursor_pos_x : i32 = DEFAULT_EDITOR_OFFSET_X
    current_line := editor.lines[editor.cursor.line_index]
    current_col_idx := editor.cursor.col_index

    if current_col_idx == 0 {
        return DEFAULT_EDITOR_OFFSET_X
    }

    for char in current_line.chars[:current_col_idx] {
        cursor_pos_x += char.glyph.advance
    }

    offset_diff : i32 = 0
    if editor.editor_offset_x < DEFAULT_EDITOR_OFFSET_X {
        offset_diff = DEFAULT_EDITOR_OFFSET_X - editor.editor_offset_x
    }

    // @todo: cursor pos x can be bigger than the editor clip (that is correct). It means that the line is going of the viewport.
    // When it does happen, decrease the editor offset and set the max cursor pos x which will be current window_width
    // Cursor x can not be bigger than window width, because then, the cursor is off the screen
    return cursor_pos_x - offset_diff
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
    if editor.lines_end > i32(len(editor.lines)) {
        editor.lines_end = i32(len(editor.lines))
    }
}

// @fix: there is a bug somewhere here!!!!
@(private = "file")
retain_cursor_column :: proc(editor: ^Editor) {
    total_glyph_width : i32 = 0
    current_line_data := editor.lines[editor.cursor.line_index].chars

    if int(editor.cursor.memorized_col_index) >= len(current_line_data) {
        for c in current_line_data {
            total_glyph_width += c.glyph.advance
        }
    } else {
        for c in current_line_data[:editor.cursor.memorized_col_index] {
            total_glyph_width += c.glyph.advance
        }
    }

    if len(current_line_data) == 0 {
        editor.cursor.col_index = 0
        editor.cursor.x = calculate_cursor_pos_on_line(editor)
    } else if len(current_line_data) - 1 > int(editor.cursor.memorized_col_index) {
        editor.cursor.col_index = editor.cursor.memorized_col_index
        editor.cursor.x = editor.editor_offset_x + total_glyph_width
    } else {
        editor.cursor.col_index = i32(len(current_line_data))
        editor.cursor.x = editor.editor_offset_x + total_glyph_width
    }
}

editor_get_current_line_width :: proc(editor: ^Editor) -> i32 {
    result: i32
    for c in editor.lines[editor.cursor.line_index].chars {
        result += c.glyph.advance
    }
    return result;
}
