package main

import "core:fmt"
import sdl "vendor:sdl2"
import ttf "vendor:sdl2/ttf"

@(private = "file") ATLAS_H :: 1024
@(private = "file") ATLAS_W :: 1024
@(private = "file") COLS :: 16
@(private = "file") ROWS :: 10

// for ASCII; Exclude control characters
@(private = "file") FIRST_CODE_POINT :: 32 // space
@(private = "file") LAST_CODE_POINT :: 126 // ~ (tilde)
@(private = "file") MAX_GLYPHS :: (LAST_CODE_POINT - FIRST_CODE_POINT + 1) // ASCII without control chars

Atlas :: struct {
    texture: ^sdl.Texture,
    surface: ^sdl.Surface,
    height: i32,
    width: i32,
    font_line_skip: i32, // vertical step for going to the next line of text.
    font_ascent: i32, // @explain
    font_descent: i32, // @explain
    glyphs: map[int]Glyph
}

Glyph :: struct {
    rect: sdl.Rect,
    width, height: i32,
    advance: i32, // how far to move the pen after drawing
    bearing_x, bearing_y: i32, // bearingY: height above baseline (use ttf.GlyphMetrics32)
}

build_atlas :: proc(renderer: ^sdl.Renderer, font: ^ttf.Font, atlas: ^Atlas) {
    atlas.font_line_skip = ttf.FontLineSkip(font)
    atlas.font_ascent = ttf.FontAscent(font)
    atlas.font_descent = ttf.FontDescent(font)

    max_w : i32 = 1
    max_h : i32 = 1
    for code_point in FIRST_CODE_POINT..=LAST_CODE_POINT {
        // Render glyph bitmap
        surface := ttf.RenderGlyph32_Blended(font, rune(code_point), {255, 255, 255, 255})
        if surface == nil {
            fmt.eprintln("No surface found: ", code_point)
            continue;
        }

        defer sdl.FreeSurface(surface)

        if ttf.GlyphIsProvided32(font, rune(code_point)) == 0 {
            fmt.eprintln("Glyph is not provided: ", ttf.GetError())
            return
        }

        // Get metrics
        min_x, max_x, min_y, max_y, adv : i32;
        if ttf.GlyphMetrics32(font, rune(code_point), &min_x, &max_x, &min_y, &max_y, &adv) != 0 {
            fmt.eprintln("Could not get GlyphMetrics32: ", ttf.GetError())
            return
        }

        glyph_w := max_x - min_x
        glyph_h := max_y - min_y
        if glyph_w > max_w {
            max_w = glyph_w;
        }

        if glyph_h > max_h {
            max_h = glyph_h
        }
    }

    pad : i32 = 3
    cell_w := max_w + pad * 2
    cell_h := max_h + EDITOR_FONT_SIZE
    atlas_w := COLS * cell_w
    atlas_h := ROWS * cell_h

    pixel_format : sdl.PixelFormatEnum = .RGBA8888
    atlas.surface = sdl.CreateRGBSurfaceWithFormat(0, atlas_w, atlas_h, 32, u32(pixel_format))
    if atlas.surface == nil {
        fmt.eprintln("Could not create atlas' surface: ", sdl.GetError())
        return
    }

    // Atlas background transparent
    sdl.FillRect(atlas.surface, nil, sdl.MapRGBA(atlas.surface.format, 0, 0, 0, 0));

    for cp in FIRST_CODE_POINT..=LAST_CODE_POINT {
        col := i32(cp % COLS)
        row := i32(cp / COLS)
        cell : sdl.Rect = { col * cell_w, row * cell_h, cell_w, cell_h };

        if ttf.GlyphIsProvided32(font, rune(cp)) == 0 {
            continue
        }

        min_x, max_x, min_y, max_y, adv : i32;
        if ttf.GlyphMetrics32(font, rune(cp), &min_x, &max_x, &min_y, &max_y, &adv) != 0 {
            continue
        }

        glyph_surface := ttf.RenderGlyph32_Blended(font, rune(cp), {255,255,255,255})
        if glyph_surface == nil {
            fmt.eprintln("could not get glyph_surface")
            continue
        }

        defer sdl.FreeSurface(glyph_surface)

        // Position the glyph bitmap inside the cell so that the glyph's baseline aligns consistently.
        // Baseline of the cell: top + pad + ascent
        baseline_y := cell.y + pad + atlas.font_ascent
        // Top-left where bitmap should go:
        dst_x := cell.x + pad + min_x        // minx = bearingX
        dst_y := baseline_y

        dst : sdl.Rect = { dst_x, dst_y, glyph_surface.w, glyph_surface.h }
        src : sdl.Rect = { 0, 0, glyph_surface.w, glyph_surface.h }

        sdl.BlitSurface(glyph_surface, &src, atlas.surface, &dst);

        atlas.glyphs[cp] = Glyph{
            rect = dst,
            advance = adv,
            bearing_x = min_x,
            bearing_y = max_y,
            width = glyph_surface.w,
            height = glyph_surface.h
        }
    }

    atlas.texture = sdl.CreateTextureFromSurface(renderer, atlas.surface)
    if atlas.texture == nil {
        fmt.eprintln("Could not create atlas' texture: ", sdl.GetError())
        return
    }

    sdl.SetTextureBlendMode(atlas.texture, .BLEND)

    // For debug purpouse
    sdl.SaveBMP(atlas.surface, "test.bmp")
}

get_glyph_from_atlas :: proc(atlas: ^Atlas, code_point: int) -> ^Glyph {
    glyph := &atlas.glyphs[code_point]
    if glyph == nil {
        return nil
    }

    return glyph
}

draw_text :: proc(renderer: ^sdl.Renderer, atlas: ^Atlas, lines: [dynamic]Line) {
    pen_x : i32 = 0
    baseline : i32 = 0 + atlas.font_ascent

    for line in lines {
        for character in line.chars {
            code_point := int(character)
            glyph := get_glyph_from_atlas(atlas, code_point)

            // @todo: what to do if a control character
            if glyph == nil {
                continue
            }

            glyph_x := pen_x + glyph.bearing_x
            glyph_y := baseline //- glyph.bearing_y
            destination : sdl.Rect = {glyph_x, glyph_y, glyph.width, glyph.height}

            sdl.RenderCopy(renderer, atlas.texture, &glyph.rect, &destination)
            pen_x += glyph.advance;
        }

        baseline += atlas.font_line_skip
        pen_x = 0
    }
}

