package main

import "core:fmt"
import "core:strings"
import "core:unicode/utf8"
import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"


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

    set_vsync := sdl.SetRenderVSync(renderer, 1) // @note(kristen): locks to display's refresh rate
    if !set_vsync {
        fmt.eprintln("Failed to set renderer VSync!")

        set_vsync_adaptive := sdl.SetRenderVSync(renderer, sdl.RENDERER_VSYNC_ADAPTIVE)
        if !set_vsync_adaptive {
            fmt.eprintln("Failed to set renderer VSync as adaptive!")
        }
    }

    if !ttf.Init() {
        fmt.eprintln("Failed to initialize ttf library", sdl.GetError())
        return
    }

    defer ttf.Quit()

    font := ttf.OpenFont("./fonts/IBMPlexMono-Regular.ttf", DEFAULT_EDITOR_FONT_SIZE)
    if font == nil {
        fmt.eprintln("Failed to load font: ", sdl.GetError())
        return
    }
    defer ttf.CloseFont(font)

    ttf.SetFontKerning(font, true)

    atlas := new(Atlas)
    build_atlas(renderer, font, atlas)

    editor_lines : [dynamic]Line
    line_chars : [dynamic]rune
    append(&editor_lines, Line{
        x = 0,
        y = 0,
        chars = line_chars,
    })

    buffers : [dynamic]Gap_Buffer

    editor := Editor{
        editor_gutter_clip = sdl.Rect{0, 0, EDITOR_GUTTER_WIDTH, window_height},
        editor_clip = sdl.Rect{
            EDITOR_GUTTER_WIDTH,
            0,
            window_width - EDITOR_GUTTER_WIDTH,
            window_height - EDITOR_BOTTOM_PADDING
        },
        editor_offset_x = EDITOR_GUTTER_WIDTH,
        cursor_right_side_cutoff_line = window_width - EDITOR_RIGHT_SIDE_CUTOFF,
        renderer = renderer,
        font = font,
        lines = &editor_lines,
        lines2 = &buffers,
        glyph_atlas = atlas,
        cursor = Cursor{
            memorized_col_index = 0,
            line_index = 0,
            col_index = 0,
            x = EDITOR_GUTTER_WIDTH,
            y = 0,
            fat_cursor = atlas.glyphs[32].advance,
            skinny_cursor = 2,
        },
        cmd_line = Command_Line{
            cursor = &Cursor{
                visible = false,
                x = 0,
                col_index = 0
            },
            input = new([dynamic]rune)
        },
        line_height = atlas.font_line_skip,
        vim = Vim{
            enabled = true,
            mode = .NORMAL
        },
        theme = Theme{
            text_color = sdl.Color{217,189,165, 0},
            background_color = sdl.Color{13,54,21, 0},
            keyword_color = sdl.Color{255, 255, 255, 255},
            string_color = sdl.Color{59,224,195,0},
            line_nr_color = sdl.Color{255, 255, 255, 50},
            comment_color = sdl.Color{189,181,185, 0},
            font_size = DEFAULT_EDITOR_FONT_SIZE
        },
        active_viewport = .EDITOR
    }

    editor_on_file_open_v2(&editor, "/home/salakris/Documents/dev/slate/tmp/test.txt")
    //editor_on_file_open(&editor, "/home/salakris/Documents/dev/slate/vim_motion.odin")
    //editor_on_file_open(&editor, "/home/salakris/Downloads/20MB-TXT-FILE.txt")
    //editor_on_file_open(&editor, "/home/salakris/Downloads/50MB-TXT-FILE.txt")
    //editor_on_file_open(&editor, "/home/salakris/Downloads/sample-2mb-text-file.txt")

    editor_update_visible_lines(&editor)
    assert(len(editor.lines) > 0, "Editor lines should have at least one line on startup")

    cursor_visible := true
    blink_interval : i32 = 500
    next_blink := sdl.GetTicks() + u64(blink_interval)

    start_time := sdl.GetTicks()
    frame_count := 0
    fps: u64 = 0.0

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
                editor.editor_clip.h = window_height - EDITOR_BOTTOM_PADDING
                editor.editor_clip.w = window_width - EDITOR_GUTTER_WIDTH
                editor.editor_gutter_clip.h = window_height
                editor.cursor_right_side_cutoff_line = window_width - EDITOR_RIGHT_SIDE_CUTOFF
                editor_update_visible_lines(&editor)
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

                if editor.active_viewport == .EDITOR {
                    if editor.vim.enabled {
                        if editor.vim.mode == .NORMAL || editor.vim.mode == .PENDING {
                            exec_vim_motion_normal_mode(char, &editor)
                        } else if editor.vim.mode == .INSERT {
                            //editor_on_text_input(&editor, int(char))
                            editor_on_text_input_v2(&editor, int(char))
                        }
                    } else {
                        editor_on_text_input(&editor, int(char))
                    }

                    // cancel cursor blinking while typing
                    cursor_visible = true
                    next_blink = sdl.GetTicks() + u64(blink_interval)
                    break
                }

                if editor.active_viewport == .COMMAND_LINE {
                    editor_command_line_on_text_input(&editor, int(char))
                }

                break
            case .KEY_DOWN:
                cursor_visible = true
                next_blink = sdl.GetTicks() + u64(blink_interval)

                keycode := event.key.scancode
                if keycode == .TAB {
                    editor_on_tab(&editor)
                    break
                }
                if keycode == .RETURN {
                    if editor.active_viewport == .EDITOR {
                        if editor.vim.enabled && editor.vim.mode == .NORMAL {
                            editor_move_cursor_down(&editor)
                            break
                        }

                        editor_on_return(&editor)
                        break
                    }

                    if editor.active_viewport == .COMMAND_LINE {
                        editor_cmd_line_on_return(&editor)
                    }
                    break
                }
                if keycode == .BACKSPACE {
                    if editor.active_viewport == .EDITOR {
                        editor_on_backspace(&editor)
                        break
                    }

                    if editor.active_viewport == .COMMAND_LINE {
                        editor_cmd_line_on_backspace(&editor)
                    }
                    break
                }

                if keycode == .UP {
                    editor_move_cursor_up(&editor)
                    break
                }

                if keycode == .DOWN {
                    editor_move_cursor_down(&editor)
                    break
                }

                if keycode == .LEFT {
                    //editor_move_cursor_left(&editor)
                    editor_move_cursor_left_v2(&editor)
                    break
                }

                if keycode == .RIGHT {
                    //editor_move_cursor_right(&editor)
                    editor_move_cursor_right_v2(&editor)
                    break
                }

                if keycode == .ESCAPE {
                    if editor.active_viewport == .COMMAND_LINE {
                        editor.active_viewport = .EDITOR
                        reset_cmd_line(&editor)
                    }

                    if editor.vim.enabled {
                        editor.vim.mode = .NORMAL
                        clear_vim_motion_store(&editor)
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
            sdl.SetRenderDrawColor(
                renderer,
                editor.theme.background_color.r,
                editor.theme.background_color.g,
                editor.theme.background_color.b,
                editor.theme.background_color.a)

            // Drawing should be done between RenderClear and RenderPresent
            sdl.RenderClear(renderer)

            // draw statusline
            {
                rect := editor_draw_rect(
                          renderer,
                          sdl.Color{217,185, 155, 0},
                          {0, window_height - COMMAND_LINE_HEIGHT - 30},
                          window_width,
                          COMMAND_LINE_HEIGHT)

                draw_custom_text(
                    renderer,
                    editor.glyph_atlas,
                    get_vim_mode_text(editor.vim.mode),
                    {rect.x, rect.y - 5})
            }

            // editor clip
            sdl.SetRenderClipRect(renderer, &editor.editor_clip)
            if cursor_visible && editor.active_viewport == .EDITOR {
                cursor_width := editor.cursor.fat_cursor
                if editor.vim.mode == .INSERT {
                    cursor_width = editor.cursor.skinny_cursor
                }
                editor_draw_rect(
                    renderer,
                    sdl.Color{255, 255, 255, 255},
                    {editor.cursor.x, editor.cursor.y + 6},
                    cursor_width,
                    editor.theme.font_size)
            }
            //editor_draw_text(&editor)
            editor_draw_text_v2(&editor)

            sdl.SetRenderClipRect(renderer, nil)

            // gutter clip
            sdl.SetRenderClipRect(renderer, &editor.editor_gutter_clip)
            editor_draw_line_nr(&editor)
            sdl.SetRenderClipRect(renderer, nil)


            // command line and its cursor
            if editor.active_viewport == .COMMAND_LINE {
                //editor_draw_rect(renderer, sdl.Color{255, 255, 255, 255}, {0, window_height - COMMAND_LINE_HEIGHT}, window_width, COMMAND_LINE_HEIGHT)
                editor_draw_rect(
                    renderer,
                    sdl.Color{255, 255, 255, 255},
                    {editor.cmd_line.cursor.x, window_height - COMMAND_LINE_HEIGHT},
                    10,
                    editor.theme.font_size)

                editor_command_line_draw_text(&editor, window_height - COMMAND_LINE_HEIGHT - 5)
            }

            sdl.RenderPresent(renderer)
        }

    }

    // Cleanup
    {
        stop_text_input := sdl.StopTextInput(window)
        if !stop_text_input {
            fmt.eprintln("Could not stop text input: ", sdl.GetError())
        }

        delete(editor.glyph_atlas.glyphs)
        delete(editor.lines^)
        delete(editor.lines2^)
        delete(editor.cmd_line.input^)
    }
}
