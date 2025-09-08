package main

import sdl "vendor:sdl2"

@(private) EDITOR_FONT_SIZE :: 30

Editor :: struct {
    renderer: ^sdl.Renderer,
    glyph_atlas: ^Atlas,
    lines: [dynamic]Line,
}

Line :: struct {
    chars: [dynamic]rune,
    x, y: i32,
}

Cursor :: struct {
    x, y: i32
}

// read file line by line
read_file :: proc() {
} 

