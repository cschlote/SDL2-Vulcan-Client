/** Builds font atlases and emits textured text geometry.
 *
 * Loads fonts through FreeType, derives glyph metrics, creates atlas textures,
 * and appends screen-space text quads for the UI and overlay layers. The atlas
 * output is used by source/vulkan/ui.d and source/vulkan/ui_layer.d, while the
 * wider build pipeline is described in docs/vulkan-quickstart.md and
 * docs/shaders.md.
 *
 * See_Also:
 *   source/vulkan/ui.d
 *   source/vulkan/ui_layer.d
 *   docs/vulkan-quickstart.md
 *   docs/shaders.md
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.font;

import bindbc.freetype;
import std.algorithm : max;
import std.exception : enforce;
import std.file : exists;
import std.math : ceil, isInfinity, isNaN, sqrt;
import std.process : environment;
import std.string : indexOf, toStringz;

import vulkan.pipeline : Vertex;

/** Describes one glyph stored in a font atlas.
 *
 * The glyph record keeps the rendering metrics and atlas coordinates together
 * so the UI code can place text without duplicating FreeType queries.
 */
struct FontGlyph
{
    /** Horizontal advance in pixels. */
    float advance;
    /** Horizontal bearing in pixels. */
    float bearingX;
    /** Vertical bearing in pixels. */
    float bearingY;
    /** Glyph bitmap width in pixels. */
    float width;
    /** Glyph bitmap height in pixels. */
    float height;
    /** Minimum atlas U coordinate. */
    float u0;
    /** Minimum atlas V coordinate. */
    float v0;
    /** Maximum atlas U coordinate. */
    float u1;
    /** Maximum atlas V coordinate. */
    float v1;
}

/** Holds one FreeType-rasterized atlas and the glyph metrics for it.
 *
 * The renderer keeps one atlas per requested text size so the UI layer can draw
 * small, medium, and large labels without resampling.
 */
struct FontAtlas
{
    /** Requested pixel height for the font. */
    uint pixelHeight;
    /** Atlas width in pixels. */
    uint width;
    /** Atlas height in pixels. */
    uint height;
    /** Distance from the top of a line to the baseline. */
    float ascent;
    /** Distance from the baseline to the bottom of a line. */
    float descent;
    /** Baseline-to-baseline distance in pixels. */
    float lineHeight;
    /** Rasterized glyph metrics and texture coordinates. */
    FontGlyph[char] glyphs;
    /** RGBA atlas pixels in row-major order. */
    ubyte[] pixels;
}

private enum defaultGlyphSet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 .,:;!?/\\+-()[]%";

/** Chooses a reasonable system font path for the current platform.
 *
 * The renderer consults this helper when no explicit font path was supplied,
 * which keeps the sample runnable on a fresh system.
 *
 *
 * @returns A usable font file path.
 */
string selectDefaultFontPath()
{
    const overrideFontPath = environment.get("SDL2_VULCAN_CLIENT_FONT_PATH", "");
    if (overrideFontPath.length != 0 && overrideFontPath.exists)
        return overrideFontPath.idup;

    version(linux)
    {
        foreach (candidate; [
            "/usr/share/fonts/noto/NotoSans-Regular.ttf",
            "/usr/share/fonts/TTF/DejaVuSans.ttf",
            "/usr/share/fonts/liberation/LiberationSans-Regular.ttf",
        ])
        {
            if (candidate.exists)
                return candidate.idup;
        }
    }

    version(OSX)
        return "/System/Library/Fonts/Supplemental/Arial Unicode.ttf".idup;

    version(Windows)
        return "C:/Windows/Fonts/arial.ttf".idup;

    return "/usr/share/fonts/TTF/DejaVuSans.ttf".idup;
}

/** Chooses a reasonable system monospace font path for the current platform. */
string selectDefaultMonospaceFontPath()
{
    const overrideFontPath = environment.get("SDL2_VULCAN_CLIENT_MONO_FONT_PATH", "");
    if (overrideFontPath.length != 0 && overrideFontPath.exists)
        return overrideFontPath.idup;

    version(linux)
    {
        foreach (candidate; [
            "/usr/share/fonts/noto/NotoSansMono-Regular.ttf",
            "/usr/share/fonts/TTF/DejaVuSansMono.ttf",
            "/usr/share/fonts/liberation/LiberationMono-Regular.ttf",
        ])
        {
            if (candidate.exists)
                return candidate.idup;
        }
    }

    version(OSX)
        return "/System/Library/Fonts/Menlo.ttc".idup;

    version(Windows)
        return "C:/Windows/Fonts/consola.ttf".idup;

    return "/usr/share/fonts/noto/NotoSansMono-Regular.ttf".idup;
}

/** Builds a FreeType-rasterized atlas for the requested glyph set.
 *
 * The resulting atlas is consumed by the UI and overlay modules, which render
 * text by appending textured quads into the shared vertex buffers.
 *
 *
 * @param fontPath = Path to the font file.
 * @param pixelHeight = Requested pixel height.
 * @param glyphSet = Characters to include in the atlas.
 * @returns A populated atlas with bitmap pixels and glyph metrics.
 */
FontAtlas buildFontAtlas(string fontPath, uint pixelHeight, string glyphSet = defaultGlyphSet)
{
    auto loadResult = loadFreeType();
    enforce(loadResult != FTSupport.noLibrary && loadResult != FTSupport.badLibrary, "loadFreeType failed.");

    FT_Library library = null;
    enforce(FT_Init_FreeType(&library) == 0, "FT_Init_FreeType failed.");
    scope (exit)
        if (library !is null)
            FT_Done_FreeType(library);

    FT_Face face = null;
    enforce(FT_New_Face(library, fontPath.toStringz, 0, &face) == 0, "FT_New_Face failed for font path: " ~ fontPath);
    scope (exit)
        if (face !is null)
            FT_Done_Face(face);

    enforce(FT_Set_Pixel_Sizes(face, 0, pixelHeight) == 0, "FT_Set_Pixel_Sizes failed.");

    string uniqueGlyphSet = glyphSet;
    if (indexOf(uniqueGlyphSet, '?') < 0)
        uniqueGlyphSet ~= "?";
    if (indexOf(uniqueGlyphSet, ' ') < 0)
        uniqueGlyphSet = " " ~ uniqueGlyphSet;

    uint maxGlyphWidth = 1;
    uint maxGlyphHeight = 1;
    float ascent = cast(float)face.size.metrics.ascender / 64.0f;
    float descent = -cast(float)face.size.metrics.descender / 64.0f;
    float lineHeight = cast(float)face.size.metrics.height / 64.0f;

    foreach (ch; uniqueGlyphSet)
    {
        enforce(FT_Load_Char(face, ch, FT_LOAD_DEFAULT) == 0, "FT_Load_Char failed while measuring glyphs.");
        enforce(FT_Render_Glyph(face.glyph, FT_Render_Mode.normal) == 0, "FT_Render_Glyph failed while measuring glyphs.");

        const bitmap = face.glyph.bitmap;
        maxGlyphWidth = max(maxGlyphWidth, cast(uint)bitmap.width);
        maxGlyphHeight = max(maxGlyphHeight, cast(uint)bitmap.rows);
    }

    const glyphCount = cast(uint)uniqueGlyphSet.length;
    const columns = cast(uint)ceil(sqrt(cast(double)glyphCount));
    const rows = cast(uint)((glyphCount + columns - 1) / columns);
    const cellWidth = maxGlyphWidth + 2;
    const cellHeight = maxGlyphHeight + 2;
    const atlasWidth = columns * cellWidth;
    const atlasHeight = rows * cellHeight;

    FontAtlas atlas;
    atlas.pixelHeight = pixelHeight;
    atlas.width = atlasWidth;
    atlas.height = atlasHeight;
    atlas.ascent = ascent;
    atlas.descent = descent;
    atlas.lineHeight = lineHeight;
    atlas.pixels.length = atlasWidth * atlasHeight * 4;

    foreach (index, ch; uniqueGlyphSet)
    {
        enforce(FT_Load_Char(face, ch, FT_LOAD_DEFAULT) == 0, "FT_Load_Char failed while building glyph atlas.");
        enforce(FT_Render_Glyph(face.glyph, FT_Render_Mode.normal) == 0, "FT_Render_Glyph failed while building glyph atlas.");

        const bitmap = face.glyph.bitmap;
        const glyphColumn = cast(uint)index % columns;
        const glyphRow = cast(uint)index / columns;
        const atlasX = glyphColumn * cellWidth + 1;
        const atlasY = glyphRow * cellHeight + 1;

        copyGlyphBitmap(atlas.pixels, atlasWidth, atlasHeight, atlasX, atlasY, bitmap);

        FontGlyph glyph;
        glyph.advance = cast(float)face.glyph.advance.x / 64.0f;
        glyph.bearingX = cast(float)face.glyph.bitmapLeft;
        glyph.bearingY = cast(float)face.glyph.bitmapTop;
        glyph.width = cast(float)bitmap.width;
        glyph.height = cast(float)bitmap.rows;
        glyph.u0 = cast(float)atlasX / cast(float)atlasWidth;
        glyph.v0 = cast(float)atlasY / cast(float)atlasHeight;
        glyph.u1 = cast(float)(atlasX + bitmap.width) / cast(float)atlasWidth;
        glyph.v1 = cast(float)(atlasY + bitmap.rows) / cast(float)atlasHeight;
        atlas.glyphs[ch] = glyph;
    }

    return atlas;
}

/** Appends text quads using the texture coordinates stored in a font atlas.
 *
 * The UI layer passes the current vertex list and a depth value so text can be
 * layered with the rest of the retained widgets and the HUD overlay.
 *
 *
 * @param vertices = Destination vertex list.
 * @param atlas = Font atlas used for the text.
 * @param text = Text to append.
 * @param x = Starting x position in pixels.
 * @param y = Starting y position in pixels.
 * @param color = Text color in RGBA format.
 * @param extentWidth = Swapchain width in pixels.
 * @param extentHeight = Swapchain height in pixels.
 * @returns Nothing.
 */
void appendText(ref Vertex[] vertices, const(FontAtlas) atlas, string text, float x, float y, float z, float[4] color, float extentWidth, float extentHeight)
{
    float cursorX = x;
    float cursorY = y;
    const baselineOffset = atlas.ascent;

    foreach (ch; text)
    {
        if (ch == '\n')
        {
            cursorX = x;
            cursorY += atlas.lineHeight;
            continue;
        }

        auto glyphPtr = ch in atlas.glyphs;
        if (glyphPtr is null)
            glyphPtr = '?' in atlas.glyphs;

        const glyph = glyphPtr is null ? FontGlyph.init : *glyphPtr;
        if (glyph.width > 0 && glyph.height > 0)
        {
            const left = cursorX + glyph.bearingX;
            const top = cursorY + baselineOffset - glyph.bearingY;
            appendTexturedQuad(vertices, left, top, left + glyph.width, top + glyph.height, z, glyph.u0, glyph.v0, glyph.u1, glyph.v1, color, extentWidth, extentHeight);
        }

        cursorX += glyph.advance;
    }
}

private void copyGlyphBitmap(ref ubyte[] atlasPixels, uint atlasWidth, uint atlasHeight, uint atlasX, uint atlasY, ref const(FT_Bitmap) bitmap)
{
    const pitch = bitmap.pitch;
    const rowStride = cast(uint)(pitch < 0 ? -pitch : pitch);
    const sourceStart = pitch < 0 ? bitmap.buffer + (bitmap.rows - 1) * rowStride : bitmap.buffer;

    foreach (row; 0 .. bitmap.rows)
    {
        const sourceRow = pitch < 0 ? sourceStart - cast(ptrdiff_t)row * rowStride : sourceStart + row * rowStride;
        foreach (column; 0 .. bitmap.width)
        {
            const sourceValue = sourceRow[column];
            const destinationIndex = ((atlasY + row) * atlasWidth + (atlasX + column)) * 4;
            atlasPixels[destinationIndex + 0] = 255;
            atlasPixels[destinationIndex + 1] = 255;
            atlasPixels[destinationIndex + 2] = 255;
            atlasPixels[destinationIndex + 3] = sourceValue;
        }
    }
}

private void appendTexturedQuad(ref Vertex[] vertices, float left, float top, float right, float bottom, float z, float u0, float v0, float u1, float v1, float[4] color, float extentWidth, float extentHeight)
{
    const safeExtentWidth = extentWidth > 0.0f && !isNaN(extentWidth) && !isInfinity(extentWidth) ? extentWidth : 1.0f;
    const safeExtentHeight = extentHeight > 0.0f && !isNaN(extentHeight) && !isInfinity(extentHeight) ? extentHeight : 1.0f;
    const x0 = left / safeExtentWidth * 2.0f - 1.0f;
    const y0 = top / safeExtentHeight * 2.0f - 1.0f;
    const x1 = right / safeExtentWidth * 2.0f - 1.0f;
    const y1 = bottom / safeExtentHeight * 2.0f - 1.0f;

    vertices ~= Vertex([x0, y0, z], color, [0.0f, 0.0f, 1.0f], [u0, v0]);
    vertices ~= Vertex([x1, y0, z], color, [0.0f, 0.0f, 1.0f], [u1, v0]);
    vertices ~= Vertex([x1, y1, z], color, [0.0f, 0.0f, 1.0f], [u1, v1]);

    vertices ~= Vertex([x0, y0, z], color, [0.0f, 0.0f, 1.0f], [u0, v0]);
    vertices ~= Vertex([x1, y1, z], color, [0.0f, 0.0f, 1.0f], [u1, v1]);
    vertices ~= Vertex([x0, y1, z], color, [0.0f, 0.0f, 1.0f], [u0, v1]);
}

unittest
{
    assert(indexOf(defaultGlyphSet, '?') >= 0);
    assert(indexOf(defaultGlyphSet, ' ') >= 0);
    assert(selectDefaultFontPath().length > 0);
}