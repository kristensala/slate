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
    rect: ^sdl.Rect,
    width, height: i32,
    advance: i32, // how far to move the pen after drawing
    bearing_x, bearing_y: i32, // bearingY: height above baseline (use ttf.GlyphMetrics32)
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

    pad : i32 = 2
    cell_w := max_w + pad * 2
    cell_h := max_h + pad * 2
    atlas_w := COLS * cell_w
    atlas_h := ROWS * cell_h

    foo : sdl.PixelFormatEnum = .RGBX8888
    atlas.surface = sdl.CreateRGBSurfaceWithFormat(0, atlas_w, atlas_h, 32, u32(foo))
    if atlas.surface == nil {
        fmt.eprintln("Could not create atlas' surface: ", sdl.GetError())
        return
    }

    // Clear to transparent/black
    sdl.FillRect(atlas.surface, nil, sdl.MapRGBA(atlas.surface.format, 0, 0, 0, 0));

    glyphs: map[int]Glyph

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
        baselineY := cell.y + pad + atlas.font_ascent
        // Top-left where bitmap should go:
        dst_x := cell.x + pad + min_x        // minx = bearingX
        dst_y := baselineY

        dst : sdl.Rect = { dst_x, dst_y, glyph_surface.w, glyph_surface.h }
        src : sdl.Rect = { 0, 0, glyph_surface.w, glyph_surface.h }

        sdl.BlitSurface(glyph_surface, &src, atlas.surface, &dst);

        atlas.glyphs[cp] = Glyph{
            rect = &dst,
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

    sdl.SaveBMP(atlas.surface, "test.bmp")
}

draw_string :: proc(atlas: Atlas, data: string) {
}

/*static inline Glyph* atlas_get(Atlas* a, int cp) {
    if (cp < FIRST_CP || cp > LAST_CP) return NULL;
    Glyph* g = &a->glyphs[cp - FIRST_CP];
    return g->valid ? g : NULL;
}

static void draw_text(SDL_Renderer* r, Atlas* a, const char* text, int x, int y, SDL_Color color) {
    // y is top-left of line; baseline is y + a->ascent
    int penX = x;
    int baseline = y + a->ascent;

    SDL_SetTextureColorMod(a->tex, color.r, color.g, color.b);
    SDL_SetTextureAlphaMod(a->tex, color.a);
    SDL_SetTextureBlendMode(a->tex, SDL_BLENDMODE_BLEND);

    for (const unsigned char* p = (const unsigned char*)text; *p; ++p) {
        unsigned char ch = *p;
        Glyph* g = atlas_get(a, ch);
        if (!g) { // simple fallback for unsupported glyphs
            penX += a->glyphs[' ' - FIRST_CP].advance;
            continue;
        }

        int gx = penX + g->bearingX;
        int gy = baseline - g->bearingY;

        SDL_Rect dst = { gx, gy, g->w, g->h };
        SDL_RenderCopy(r, a->tex, &g->uv, &dst);
        penX += g->advance;
    }
}*/
