package main

import "core:fmt"
import sdl "vendor:sdl2"
import ttf "vendor:sdl2/ttf"

@(private)
FONT_SIZE :: 20

main :: proc() {
    if sdl.Init({.VIDEO}) != 0 {
        fmt.eprintln("sdl.Init failed: ", sdl.GetError())
        return
    }
    defer sdl.Quit()

    window := sdl.CreateWindow(
        "slate_editor",
        sdl.WINDOWPOS_UNDEFINED,
        sdl.WINDOWPOS_UNDEFINED,
        1000,
        1000,
        {},
    )

    if window == nil {
        fmt.eprintln("Failed to create the window")
        return
    }

    defer sdl.DestroyWindow(window)

    // Set background color of the window
    // We must call SDL_CreateRenderer in order for draw calls to affect this window.
    renderer := sdl.CreateRenderer(window, -1, {.SOFTWARE})
    defer sdl.DestroyRenderer(renderer)

    // Load a font
    if ttf.Init() != 0 {
        fmt.eprintln("Faild to initialize ttf library", ttf.GetError())
        return
    }

    defer ttf.Quit()

    font := ttf.OpenFont("./fonts/IBMPlexMono-Regular.ttf", FONT_SIZE)
    if font == nil {
        fmt.eprintln("Failed to load font: ", ttf.GetError())
        return
    }

    defer ttf.CloseFont(font)

    // render example text
    text_color: sdl.Color = {255, 255, 255, 255}
    surface := ttf.RenderUTF8_Blended(font, "Hello", text_color)
    if surface == nil {
        fmt.eprintln("Failed to create a surface: ", ttf.GetError())
        return
    }
    defer sdl.FreeSurface(surface)

    texture := sdl.CreateTextureFromSurface(renderer, surface)
    defer sdl.DestroyTexture(texture)

    if texture == nil {
        fmt.eprintln("Failed to create a texture: ", sdl.GetError())
        return
    }

    text_width, text_height : i32 = 100, 100
    sdl.QueryTexture(texture, nil, nil, &text_width, &text_height)
    text_destination : sdl.Rect = {10, 10, text_width, text_height}

    running := true
    loop: for(running) {
        event : sdl.Event
        for sdl.PollEvent(&event) {
            #partial switch event.type {
            case .QUIT:
                running = false
                break loop
            }
        }

        sdl.SetRenderDrawColor(renderer, 255, 0, 0, 255) // red

        // Drawing should be done between RenderClear and RenderPresent
        sdl.RenderClear(renderer)

        sdl.RenderCopy(renderer, texture, nil, &text_destination)

        sdl.RenderPresent(renderer)
    }
}

