package main

import "core:fmt"
import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"
import ft "freetype"

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
    font_ascent: i32,
    font_descent: i32,
    glyphs: map[int]Glyph
}

Glyph :: struct {
    uv: sdl.Rect,
    width, height: i32,
    advance: i32, // how far to move the pen after drawing
    bearing_x, bearing_y: i32, // bearingY: height above baseline (use ttf.GlyphMetrics32)
}

build_atlas :: proc(renderer: ^sdl.Renderer, font: ^ttf.Font, atlas: ^Atlas) {
    //atlas.font_line_skip = ttf.GetFontLineSkip(font^) // this gives me random value every time

    atlas.font_line_skip = 30
    atlas.font_ascent = ttf.GetFontAscent(font^)
    atlas.font_descent = ttf.GetFontDescent(font^)

    max_w : i32 = 1
    max_h : i32 = 1
    for code_point in FIRST_CODE_POINT..=LAST_CODE_POINT {
        // Render glyph bitmap
        surface := ttf.RenderGlyph_Blended(font, u32(code_point), {255, 255, 255, 255})
        if surface == nil {
            fmt.eprintln("No surface found: ", code_point)
            continue;
        }

        defer sdl.DestroySurface(surface)

        // Get metrics
        min_x, max_x, min_y, max_y, adv : i32;
        if !ttf.GetGlyphMetrics(font, u32(code_point), &min_x, &max_x, &min_y, &max_y, &adv) {
            fmt.eprintln("Could not get GlyphMetrics32: ", sdl.GetError())
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

    atlas.surface = sdl.CreateSurface(atlas_w, atlas_h, .RGBA32)
    if atlas.surface == nil {
        fmt.eprintln("Could not create atlas' surface: ", sdl.GetError())
        return
    }

    // Atlas background transparent
    clear_bg := sdl.MapSurfaceRGBA(atlas.surface, 0, 0, 0, 0)
    sdl.FillSurfaceRect(atlas.surface, nil, clear_bg)

    for cp in FIRST_CODE_POINT..=LAST_CODE_POINT {
        col := i32(cp % COLS)
        row := i32(cp / COLS)
        cell : sdl.Rect = { col * cell_w, row * cell_h, cell_w, cell_h };

        min_x, max_x, min_y, max_y, adv : i32;
        if !ttf.GetGlyphMetrics(font, u32(cp), &min_x, &max_x, &min_y, &max_y, &adv) {
            fmt.eprintln("Could not get glpyh metrics: ", cp)
            continue
        }

        glyph_surface := ttf.RenderGlyph_Blended(font, u32(cp), {255,255,255,0})
        if glyph_surface == nil {
            fmt.eprintln("could not get glyph_surface")
            continue
        }

        defer sdl.DestroySurface(glyph_surface)

        // Position the glyph bitmap inside the cell so that the glyph's baseline aligns consistently.
        // Baseline of the cell: top + pad + ascent
        baseline_y := cell.y + pad

        // Top-left where bitmap should go:
        dst_x := cell.x + pad + min_x // minx = bearingX
        dst_y := baseline_y 

        dst : sdl.Rect = { dst_x, dst_y, glyph_surface.w, glyph_surface.h }
        src : sdl.Rect = { 0, 0, glyph_surface.w, glyph_surface.h }

        sdl.SetSurfaceBlendMode(glyph_surface, {.BLEND})
        sdl.SetSurfaceBlendMode(atlas.surface, {.BLEND_PREMULTIPLIED})
        sdl.BlitSurface(glyph_surface, nil, atlas.surface, &dst);

        atlas.glyphs[cp] = Glyph{
            uv = dst,
            advance = adv,
            bearing_x = min_x,
            bearing_y = max_y,
            width = glyph_surface.w,
            height = glyph_surface.h
        }
    }

    //sdl.SetHint(sdl.HINT_RENDER_SCALE_QUALITY, "0")
    atlas.texture = sdl.CreateTextureFromSurface(renderer, atlas.surface)
    if atlas.texture == nil {
        fmt.eprintln("Could not create atlas' texture: ", sdl.GetError())
        return
    }

    // For debug purpouse
    //sdl.SaveBMP(atlas.surface, "test.bmp")
}

get_glyph_from_atlas :: proc(atlas: ^Atlas, code_point: int) -> ^Glyph {
    glyph := &atlas.glyphs[code_point]
    if glyph == nil {
        return nil
    }

    return glyph
}

