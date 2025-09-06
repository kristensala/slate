package main

import "core:fmt"
import sdl "vendor:sdl2"
import ttf "vendor:sdl2/ttf"

ATLAS_H :: 1024
ATLAS_W :: 1024

// for ASCII; Exclude control characters
FIRST_CODE_POINT :: 32 // space
LAST_CODE_POINT :: 126 // ~ (tilde)
MAX_GLYPHS :: (LAST_CODE_POINT - FIRST_CODE_POINT + 1) // ASCII without control chars

Atlas :: struct {
    texture: ^sdl.Texture,
    height: i32,
    width: i32,
    line_skip: i32, // vertical step for going to the next line of text.
    ascent: i32,
    descent: i32,
    glyphs: [MAX_GLYPHS]Glyph
}

Glyph :: struct {
    rect: sdl.Rect,
    width, height: i32,
    advance: i32, // how far to move the pen after drawing
    bearingX, bearingY: i32, // bearingY: height above baseline (use ttf.GlyphMetrics32)
}

/*
   @todo:
   When you have tons of dynamic text
   If you’re rendering hundreds of changing strings
   (e.g., chat with rapid updates, code editors, roguelikes),
   consider a glyph atlas/bitmap font approach (cache each
   glyph once and build strings by drawing quads).

   read about "glyph atlas + batching"
   https://www.parallelrealities.co.uk/tutorials/ttf/ttf2.php
 */
build_atlas :: proc(renderer: ^sdl.Renderer, font: ^ttf.Font, atlas: ^Atlas) {
    atlas.texture = sdl.CreateTexture(renderer, .RGBX8888, .STATIC, ATLAS_W, ATLAS_H)
    if atlas.texture == nil {
        fmt.eprintln("Could not create atlas' texture: ", sdl.GetError())
        return
    }

    atlas.line_skip = ttf.FontLineSkip(font)
    atlas.ascent = ttf.FontAscent(font)
    atlas.descent = ttf.FontDescent(font)

    maxW : i32 = 1
    maxH : i32 = 1
    for code_point in FIRST_CODE_POINT..=LAST_CODE_POINT {
        if ttf.GlyphIsProvided32(font, rune(code_point)) != 0 {
            fmt.eprintln("Glyph is not povided: ", ttf.GetError())
            return
        }

        minx, maxx, miny, maxy, adv : i32;
        if ttf.GlyphMetrics32(font, rune(code_point), &minx, &maxx, &miny, &maxy, &adv) != 0 {
            fmt.eprintln("Could not get GlyphMetrics32: ", ttf.GetError())
            return
        }

        glyph_w := maxx - minx
        glyph_h := maxy - miny
        if glyph_w > maxW {
            maxW = glyph_w;
        }

        if glyph_h > maxH {
            maxH = glyph_h
        }
    }
}
