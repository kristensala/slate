package main

import sdl "vendor:sdl2"

@(private) EDITOR_FONT_SIZE :: 30

Editor :: struct {
    renderer: ^sdl.Renderer,
    glyph_atlas: ^Atlas,
    lines: [dynamic]Line,
    cursor: ^Cursor
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

// read file line by line
read_file :: proc() {
} 

