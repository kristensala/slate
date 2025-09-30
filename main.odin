package main

import "core:fmt"
import "core:strings"
import "core:unicode/utf8"
import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"
import xlib "vendor:x11/xlib"

main :: proc() {
    /*
       @note: sdl.CreateWindow already calls sdl.Init if it
       is not called, but it is still a good practice
       to call sdl.Init beforehand
     */
    if !sdl.Init({.VIDEO}) {
        fmt.eprintln("sdl.Init failed: ", sdl.GetError())
        return
    }
    defer sdl.Quit()

    window := sdl.CreateWindow(
        "slate_editor",
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

    renderer := sdl.CreateRenderer(window, nil)
    if renderer == nil {
        fmt.eprintln("Could not create a renderer: ", sdl.GetError())
        return
    }
    defer sdl.DestroyRenderer(renderer)

    if !ttf.Init() {
        fmt.eprintln("Failed to initialize ttf library", sdl.GetError())
        return
    }

    defer ttf.Quit()

    font := ttf.OpenFont("./fonts/IBMPlexMono-Regular.ttf", EDITOR_FONT_SIZE)
    if font == nil {
        fmt.eprintln("Failed to load font: ", sdl.GetError())
        return
    }
    defer ttf.CloseFont(font)
    ttf.SetFontKerning(font, true)


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
        editor_clip = sdl.Rect{EDITOR_GUTTER_WIDTH, 0, window_width - EDITOR_GUTTER_WIDTH, window_height - 60},
        editor_offset_x = EDITOR_GUTTER_WIDTH,
        cursor_right_side_cutoff_line = window_width - EDITOR_RIGHT_SIDE_CUTOFF,
        renderer = renderer,
        font = font,
        lines = &editor_lines,
        glyph_atlas = &atlas,
        cursor = Cursor{
            memorized_col_index = 0,
            line_index = 0,
            col_index = 0,
            x = EDITOR_GUTTER_WIDTH,
            y = 0
        },
        line_height = atlas.font_line_skip,
        vim_mode_enabled = true,
        vim_mode = .NORMAL
    }

    editor_on_file_open(&editor, "/home/salakris/Documents/personal/dev/raychess/main.odin")
    editor_update_visible_lines(&editor)
    assert(len(editor.lines) > 0, "Editor lines should have at least one line on startup")

    cursor_visible := true
    blink_interval : i32 = 500
    next_blink := sdl.GetTicks() + u64(blink_interval)

    start_time := sdl.GetTicks()
    frame_count := 0
    fps: u64 = 0.0

    command_line_open := false

    started_text_input := sdl.StartTextInput(window)
    if !started_text_input {
        fmt.eprintln("Could not start text input")
        return
    }

    // Main "game" loop
    running := true
    loop: for(running) {
        event : sdl.Event
        for sdl.PollEvent(&event) {
            #partial switch event.type {
            case .WINDOW_RESIZED:
                sdl.GetWindowSize(window, &window_width, &window_height)
                editor.editor_clip.h = window_height
                editor.editor_clip.w = window_width
                editor.editor_gutter_clip.h = window_height
                break
            case .QUIT:
                running = false
                break loop
            case .TEXT_INPUT:
                input := event.text.text
                input_str := strings.clone_from_cstring(input)
                defer delete(input_str)

                char, err_code := utf8.decode_rune(input_str)
                if err_code == 0 {
                    fmt.eprintln("Failed to decode rune: ", input_str)
                    break
                }

                if editor.vim_mode_enabled && editor.vim_mode == .NORMAL {
                    editor_vim_mode_normal_shortcuts(int(char), &editor)
                } else {
                    editor_on_text_input(&editor, int(char))
                }

                // cancel cursor blinking while typing
                cursor_visible = true
                next_blink = sdl.GetTicks() + u64(blink_interval)
                break
            case .KEY_DOWN:
                cursor_visible = true
                next_blink = sdl.GetTicks() + u64(blink_interval)

                keycode := event.key.scancode
                if keycode == .F1 {
                    command_line_open = !command_line_open
                    break
                }
                if keycode == .TAB {
                    editor_on_tab(&editor)
                    break
                }
                if keycode == .RETURN {
                    editor_on_return(&editor)
                    break
                }
                if keycode == .BACKSPACE {
                    editor_on_backspace(&editor)
                    break
                }

                if keycode == .UP {
                    editor_move_cursor_up(&editor, .ARROW_KEYS)
                    break
                }

                if keycode == .DOWN {
                    editor_move_cursor_down(&editor)
                    break
                }

                if keycode == .LEFT {
                    editor_move_cursor_left(&editor)
                    break
                }

                if keycode == .RIGHT {
                    editor_move_cursor_right(&editor)
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

        // Update
        {
            current_tick := sdl.GetTicks()
            if current_tick >= next_blink {
                cursor_visible = !cursor_visible
                next_blink += u64(blink_interval)
            }
            // show FPS in window title
            frame_count += 1;
            current_time := sdl.GetTicks()
            if current_time - start_time >= 1000 { // 1 second passed
                fps = u64(frame_count * 1000) / (current_time - start_time)
                fps_str := fmt.tprintf("slate_editor; FPS: %v", fps)
                fps_cstring := strings.clone_to_cstring(fps_str)
                defer delete(fps_cstring)

                sdl.SetWindowTitle(window, fps_cstring)
                frame_count = 0;
                start_time = current_time
            }
        }

        // Draw
        {

            // Set background color of the window
            sdl.SetRenderDrawColor(renderer, 6, 69, 38, 0)

            // Drawing should be done between RenderClear and RenderPresent
            sdl.RenderClear(renderer)

            // editor clip
            sdl.SetRenderClipRect(renderer, &editor.editor_clip)
            assert(editor.editor_offset_x <= EDITOR_GUTTER_WIDTH, "Editor offset should never be bigger than the default value")
            editor_draw_text(&editor)

            if cursor_visible {
                editor_draw_rect(renderer, sdl.Color{255, 255, 255, 255}, {editor.cursor.x, editor.cursor.y + 6}, 5, EDITOR_FONT_SIZE)
            }
            sdl.SetRenderClipRect(renderer, nil)

            // gutter clip
            sdl.SetRenderClipRect(renderer, &editor.editor_gutter_clip)
            editor_draw_line_nr(&editor)
            sdl.SetRenderClipRect(renderer, nil)

            // draw statusline
            rect := editor_draw_rect(renderer, sdl.Color{255, 255, 255, 255}, {0, window_height - COMMAND_LINE_HEIGHT - 40}, window_width, COMMAND_LINE_HEIGHT)
            vim_mode_text_surface := ttf.RenderText_Blended(editor.font, get_vim_mode_text(editor.vim_mode), 0, {0 ,0 , 0, 255})
            defer sdl.DestroySurface(vim_mode_text_surface)

            vim_mode_texture := sdl.CreateTextureFromSurface(editor.renderer, vim_mode_text_surface)
            defer sdl.DestroyTexture(vim_mode_texture)
            rect.w = f32(vim_mode_text_surface.w)
            sdl.RenderTexture(editor.renderer, vim_mode_texture, nil, &rect)

            /*if command_line_open {
              editor_draw_rect(renderer, sdl.Color{255, 255, 255, 255}, {0, window_height - COMMAND_LINE_HEIGHT}, window_width, COMMAND_LINE_HEIGHT)
              }*/

            sdl.RenderPresent(renderer)
        }

    }

    // Cleanup
    {
        stop_text_input := sdl.StopTextInput(window)
        if !stop_text_input {
            fmt.eprintln("Could not stop text input")
        }

        delete(editor.glyph_atlas.glyphs)
        delete(editor.lines^)
    }
}

@(private = "file")
draw :: proc(renderer: ^sdl.Renderer, editor: ^Editor) {
}

