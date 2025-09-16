package main

import "core:fmt"
import "core:strings"
import sdl "vendor:sdl2"
import ttf "vendor:sdl2/ttf"

/*
   TODO:
   - when moving with arrows and reach either the end or the beginning of the line, move to the next/previous line
   - text selection(highlighting)
 */
main :: proc() {
    /*
       @note: sdl.CreateWindow already calls sdl.Init if it
       is not called, but it is still a good practice
       to call sdl.Init beforehand
     */
    if sdl.Init({.VIDEO}) != 0 {
        fmt.eprintln("sdl.Init failed: ", sdl.GetError())
        return
    }
    defer sdl.Quit()

    window := sdl.CreateWindow(
        "slate_editor",
        sdl.WINDOWPOS_UNDEFINED,
        sdl.WINDOWPOS_UNDEFINED,
        1500,
        1000,
        {},
    )

    if window == nil {
        fmt.eprintln("Failed to create the window")
        return
    }
    defer sdl.DestroyWindow(window)

    window_width, window_height : i32
    sdl.GetWindowSize(window, &window_width, &window_height)

    renderer := sdl.CreateRenderer(window, -1, {.SOFTWARE})
    if renderer == nil {
        fmt.eprintln("Could not create a renderer: ", sdl.GetError())
        return
    }
    defer sdl.DestroyRenderer(renderer)

    if ttf.Init() != 0 {
        fmt.eprintln("Failed to initialize ttf library", ttf.GetError())
        return
    }

    defer ttf.Quit()

    font := ttf.OpenFont("./fonts/IBMPlexMono-Regular.ttf", EDITOR_FONT_SIZE)
    if font == nil {
        fmt.eprintln("Failed to load font: ", ttf.GetError())
        return
    }

    ttf.SetFontHinting(font, .LIGHT)

    defer ttf.CloseFont(font)

    atlas := Atlas{}
    build_atlas(renderer, font, &atlas)

    editor_lines : [dynamic]Line
    line_chars : [dynamic]Character_Info

    append(&editor_lines, Line{
        x = 0,
        y = 0,
        chars = line_chars,
    })

    editor := Editor{
        editor_gutter_clip = sdl.Rect{0, 0, EDITOR_GUTTER_WIDTH, window_height},
        editor_clip = sdl.Rect{EDITOR_GUTTER_WIDTH, 0, window_width - EDITOR_GUTTER_WIDTH, window_height},
        editor_offset_x = DEFAULT_EDITOR_OFFSET_X,
        renderer = renderer,
        font = font,
        lines = &editor_lines,
        glyph_atlas = &atlas,
        cursor = Cursor{
            memorized_col_index = 0,
            line_index = 0,
            col_index = 0,
            x = DEFAULT_EDITOR_OFFSET_X,
            y = 0
        },
        line_height = atlas.font_line_skip,
        vim_mode_enabled = true,
        vim_mode = .NORMAL
    }

    editor_on_file_open(&editor, "/home/salakris/.zshrc")
    editor_set_visible_lines(&editor, window)

    assert(len(editor.lines) > 0, "Editor lines should have at least one line on startup")

    cursor_visible := true
    blink_interval : i32 = 500
    next_blink := sdl.GetTicks() + u32(blink_interval)

    start_time := sdl.GetTicks()
    frame_count := 0
    fps: u32 = 0.0

    command_line_open := false

    sdl.StartTextInput()

    // Main "game" loop
    running := true
    loop: for(running) {
        event : sdl.Event
        for sdl.PollEvent(&event) {
            #partial switch event.type {
            case .WINDOWEVENT:
                if event.window.event == .RESIZED {
                    sdl.GetWindowSize(window, &window_width, &window_height)
                    editor.editor_clip.h = window_height
                    editor.editor_clip.w = window_width
                    editor.editor_gutter_clip.h = window_height
                }
                break
            case .QUIT:
                running = false
                break loop
            case .TEXTINPUT:
                input := int(event.text.text[0])

                if editor.vim_mode_enabled && editor.vim_mode == .NORMAL {
                    editor_vim_mode_normal_shortcuts(input, &editor, window)
                } else {
                    editor_on_text_input(&editor, input)
                }

                // cancel cursor blinking while typing
                cursor_visible = true
                next_blink = sdl.GetTicks() + u32(blink_interval)
                break
            case .KEYDOWN:
                cursor_visible = true
                next_blink = sdl.GetTicks() + u32(blink_interval)

                keycode := event.key.keysym.sym
                if keycode == .F1 {
                    command_line_open = !command_line_open
                    break
                }
                if keycode == .TAB {
                    editor_on_tab(&editor)
                    break
                }
                if keycode == .RETURN {
                    editor_on_return(&editor, window)
                    break
                }
                if keycode == .BACKSPACE {
                    editor_on_backspace(&editor, window)
                    break
                }

                if keycode == .UP {
                    editor_move_cursor_up(&editor, window, .ARROW_KEYS)
                    break
                }

                if keycode == .DOWN {
                    editor_move_cursor_down(&editor, window)
                    break
                }

                if keycode == .LEFT {
                    editor_move_cursor_left(&editor)
                    break
                }

                if keycode == .RIGHT {
                    editor_move_cursor_right(&editor, window)
                    break
                }

                if keycode == .ESCAPE {
                    if editor.vim_mode_enabled && editor.vim_mode == .INSERT {
                        editor.vim_mode = .NORMAL
                    }
                }
                break
            }
        }

        current_tick := sdl.GetTicks()
        if current_tick >= next_blink {
            cursor_visible = !cursor_visible
            next_blink += u32(blink_interval)
        }

        // Set background color of the window
        sdl.SetRenderDrawColor(renderer, 6, 69, 38, 0)

        // Drawing should be done between RenderClear and RenderPresent
        sdl.RenderClear(renderer)

        // editor clip
        sdl.RenderSetClipRect(renderer, &editor.editor_clip)
        assert(editor.editor_offset_x <= DEFAULT_EDITOR_OFFSET_X, "Editor offset should never be bigger than the default value")
        editor_draw_text(&editor)

        if cursor_visible {
            assert(editor.cursor.x >= editor.editor_offset_x, "Cursor is off editor on x axis, left side of the editor")
            editor_draw_rect(renderer, sdl.Color{255, 255, 255, 255}, {editor.cursor.x, editor.cursor.y + 6}, 5, EDITOR_FONT_SIZE)
        }
        sdl.RenderSetClipRect(renderer, nil)

        // gutter clip
        sdl.RenderSetClipRect(renderer, &editor.editor_gutter_clip)
        editor_draw_line_nr(&editor)
        sdl.RenderSetClipRect(renderer, nil)

        if command_line_open {
            editor_draw_rect(renderer, sdl.Color{255, 255, 255, 255}, {0, window_height - COMMAND_LINE_HEIGHT}, window_width, COMMAND_LINE_HEIGHT)
        }

        sdl.RenderPresent(renderer)

        // show FPS in window title
        frame_count += 1;
        current_time := sdl.GetTicks();
        if current_time - start_time >= 1000 { // 1 second passed
            fps = u32(frame_count * 1000) / (current_time - start_time)
            fps_str := fmt.tprintf("slate_editor; FPS: %v", fps)
            fps_cstring := strings.clone_to_cstring(fps_str)
            defer delete(fps_cstring)
            sdl.SetWindowTitle(window, fps_cstring)
            frame_count = 0;
            start_time = current_time;
        }
    }

    sdl.StopTextInput()
}

