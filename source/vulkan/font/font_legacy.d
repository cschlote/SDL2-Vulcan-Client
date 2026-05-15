/** Builds font atlases and emits textured text geometry.
 *
 * Loads fonts through FreeType, caches glyph metrics in a per-size atlas, and
 * appends screen-space text quads for the UI and overlay layers. The atlas
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
module vulkan.font.font_legacy;
import std.format;

import bindbc.freetype;
import std.algorithm : max;
import std.exception : enforce;
import std.file : exists;
import std.math : abs, ceil, isInfinity, isNaN, sqrt;
import std.process : environment;
import std.string : indexOf, toStringz;

import logging : logLine, logLineVerbose;
import vulkan.pipeline : Vertex;

/** Glyph metrics and atlas coordinates for one code point.
 *
 * The renderer caches FreeType query results here so later text layout and
 * quad generation can work without repeating glyph lookups or bitmap scans.
 * This keeps text rendering deterministic and avoids repeated FreeType work
 * during frame updates.
 */
struct FontGlyph
{
    float advance; /// Horizontal advance in pixels.
    float bearingX; /// Horizontal bearing in pixels.
    float bearingY; /// Vertical bearing in pixels.
    float width; /// Glyph bitmap width in pixels.
    float height; /// Glyph bitmap height in pixels.
    float u0; /// Minimum atlas U coordinate.
    float v0; /// Minimum atlas V coordinate.
    float u1; /// Maximum atlas U coordinate.
    float v1; /// Maximum atlas V coordinate.
}

/** FreeType-rasterized atlas and glyph metrics for one text size.
 *
 * The renderer keeps one atlas per requested size so UI code can measure and
 * render consistently without re-rasterizing glyphs for every widget frame.
 * This is the central cache for the font subsystem and the reason the module
 * exists as a separate layer above the UI code.
 */
struct FontAtlas
{
    uint pixelHeight; /// Requested pixel height for the font.
    uint width; /// Atlas width in pixels.
    uint height; /// Atlas height in pixels.
    float ascent; /// Distance from the top of a line to the baseline.
    float descent; /// Distance from the baseline to the bottom of a line.
    float lineHeight; /// Baseline-to-baseline distance in pixels.
    FontGlyph[dchar] glyphs; /// Rasterized glyph metrics and texture coordinates.
    float[dchar][dchar] kerning; /// Optional kerning adjustments indexed by left and right code point.
    ubyte[] pixels; /// RGBA atlas pixels in row-major order.
}

/** Default glyph coverage when no custom glyph set is supplied. */
private enum defaultGlyphSet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 .,:;!?/\\+-()[]%";

/** Chooses a reasonable system font path for the current platform.
 *
 * Returns:
 *   A usable font file path.
 */
string selectDefaultFontPath()
{
    const overrideFontPath = environment.get("SDL2_VULCAN_CLIENT_FONT_PATH", "");
    if (overrideFontPath.length != 0 && overrideFontPath.exists)
    {
        logLineVerbose("Font path override selected: ", overrideFontPath);
        return overrideFontPath.idup;
    }

    version(linux)
    {
        foreach (candidate; [
            "/usr/share/fonts/noto/NotoSans-Regular.ttf",
            "/usr/share/fonts/TTF/DejaVuSans.ttf",
            "/usr/share/fonts/liberation/LiberationSans-Regular.ttf",
        ])
        {
            if (candidate.exists)
            {
                logLineVerbose("Font path candidate selected: ", candidate);
                return candidate.idup;
            }
        }
    }

    version(OSX)
        return "/System/Library/Fonts/Supplemental/Arial Unicode.ttf".idup;

    version(Windows)
    {
        logLineVerbose("Font path default selected: C:/Windows/Fonts/arial.ttf");
        return "C:/Windows/Fonts/arial.ttf".idup;
    }

    logLineVerbose("Font path fallback selected: /usr/share/fonts/TTF/DejaVuSans.ttf");
    return "/usr/share/fonts/TTF/DejaVuSans.ttf".idup;
}

/** Chooses a reasonable system monospace font path for the current platform.
 *
 * Returns:
 *   A usable monospace font file path.
 */
string selectDefaultMonospaceFontPath()
{
    const overrideFontPath = environment.get("SDL2_VULCAN_CLIENT_MONO_FONT_PATH", "");
    if (overrideFontPath.length != 0 && overrideFontPath.exists)
    {
        logLineVerbose("Monospace font path override selected: ", overrideFontPath);
        return overrideFontPath.idup;
    }

    version(linux)
    {
        foreach (candidate; [
            "/usr/share/fonts/noto/NotoSansMono-Regular.ttf",
            "/usr/share/fonts/TTF/DejaVuSansMono.ttf",
            "/usr/share/fonts/liberation/LiberationMono-Regular.ttf",
        ])
        {
            if (candidate.exists)
            {
                logLineVerbose("Monospace font path candidate selected: ", candidate);
                return candidate.idup;
            }
        }
    }

    version(OSX)
        return "/System/Library/Fonts/Menlo.ttc".idup;

    version(Windows)
    {
        logLineVerbose("Monospace font path default selected: C:/Windows/Fonts/consola.ttf");
        return "C:/Windows/Fonts/consola.ttf".idup;
    }

    logLineVerbose("Monospace font path fallback selected: /usr/share/fonts/noto/NotoSansMono-Regular.ttf");
    return "/usr/share/fonts/noto/NotoSansMono-Regular.ttf".idup;
}

/** Builds a FreeType-rasterized atlas for the requested glyph set.
 *
 * The resulting atlas is consumed by the UI and overlay modules, which render
 * text by appending textured quads into the shared vertex buffers.
 *
 * Params:
 *   fontPath = Path to the font file.
 *   pixelHeight = Requested pixel height.
 *   glyphSet = Characters to include in the atlas.
 *
 * Returns:
 *   A populated atlas with bitmap pixels and glyph metrics.
 */
FontAtlas buildFontAtlas(string fontPath, uint pixelHeight, string glyphSet = defaultGlyphSet)
{
    logLine("Building font atlas: ", fontPath, " @ ", pixelHeight, "px");
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
    {
        logLineVerbose("Glyph set missing fallback '?', appending it.");
        uniqueGlyphSet ~= "?";
    }
    if (indexOf(uniqueGlyphSet, ' ') < 0)
    {
        logLineVerbose("Glyph set missing space, prepending it.");
        uniqueGlyphSet = ' ' ~ uniqueGlyphSet;
    }

    uint maxGlyphWidth = 1;
    uint maxGlyphHeight = 1;
    size_t kerningPairCount = 0;
    float ascent = cast(float)face.size.metrics.ascender / 64.0f;
    float descent = -cast(float)face.size.metrics.descender / 64.0f;
    float lineHeight = cast(float)face.size.metrics.height / 64.0f;

    logLineVerbose("Atlas glyph request count: ", uniqueGlyphSet.length, ", ascent=", ascent, ", descent=", descent, ", lineHeight=", lineHeight);

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

    foreach (leftChar; uniqueGlyphSet)
    {
        const leftGlyphIndex = FT_Get_Char_Index(face, leftChar);
        foreach (rightChar; uniqueGlyphSet)
        {
            const rightGlyphIndex = FT_Get_Char_Index(face, rightChar);

            FT_Vector kerningVector;
            if (FT_Get_Kerning(face, leftGlyphIndex, rightGlyphIndex, 0, &kerningVector) == 0)
            {
                const kerningPixels = cast(float)kerningVector.x / 64.0f;
                if (kerningPixels != 0.0f)
                {
                    atlas.kerning[leftChar][rightChar] = kerningPixels;
                    kerningPairCount++;
                }
            }
        }
    }

    logLine("Built font atlas: glyphs=", atlas.glyphs.length, ", kerning pairs=", kerningPairCount, ", size=", atlas.width, "x", atlas.height);
    logLineVerbose("Atlas pixel buffer size: ", atlas.pixels.length, ", max glyph size=", maxGlyphWidth, "x", maxGlyphHeight, ", font path=", fontPath);

    return atlas;
}

/** Collects a Unicode code-point set from a corpus of strings.
 *
 * The helper preserves first-seen order, which makes it suitable as input for
 * atlas generation when translation files are scanned into a glyph table.
 * A space and the fallback glyph are appended if they were not already seen.
 *
 * Params:
 *   texts = Source strings, usually gathered from translations or UI copy.
 *
 * Returns:
 *   A UTF-8 string containing each unique code point once.
 */
string collectGlyphSet(const(string)[] texts)
{
    bool[dchar] seen;
    string glyphSet;

    logLineVerbose("collectGlyphSet: input strings=", texts.length);

    foreach (text; texts)
    {
        foreach (ch; text)
        {
            if (ch == '\n' || ch == '\r' || ch in seen)
                continue;

            seen[ch] = true;
            glyphSet ~= ch;
        }
    }

    if (' ' !in seen)
        glyphSet ~= ' ';
    if ('?' !in seen)
        glyphSet ~= '?';

    logLineVerbose("collectGlyphSet: output code points=", glyphSet.length);

    return glyphSet;
}

/** Measures the rendered width of the supplied text using atlas glyph metrics.
 *
 * Params:
 *   atlas = Font atlas used for measuring.
 *   text = UTF-8 text to measure.
 *
 * Returns:
 *   The width in pixels of the widest rendered line.
 */
float measureTextWidth(ref const(FontAtlas) atlas, string text)
{
    float widestWidth = 0.0f;
    float cursorX = 0.0f;
    float lineLeft = 0.0f;
    float lineRight = 0.0f;
    bool lineHasGlyph = false;
    dchar previousChar = '\0';
    size_t lineCount = 1;

    void commitLine()
    {
        const renderedLeft = lineLeft < 0.0f ? lineLeft : 0.0f;
        const renderedRight = lineRight > cursorX ? lineRight : cursorX;
        const lineWidth = renderedRight - renderedLeft;
        widestWidth = lineWidth > widestWidth ? lineWidth : widestWidth;

        logLineVerbose("measureTextWidth line ", lineCount, ": width=", lineWidth, ", renderedLeft=", renderedLeft, ", renderedRight=", renderedRight);
        lineCount++;

        cursorX = 0.0f;
        lineLeft = 0.0f;
        lineRight = 0.0f;
        lineHasGlyph = false;
        previousChar = '\0';
    }

    foreach (ch; text)
    {
        if (ch == '\n')
        {
            commitLine();
            continue;
        }

        if (previousChar != '\0')
        {
            const leftKerningPtr = previousChar in atlas.kerning;
            if (leftKerningPtr !is null)
            {
                const kerningPtr = ch in *leftKerningPtr;
                if (kerningPtr !is null)
                    cursorX += *kerningPtr;
            }
        }

        const glyphPtr = ch in atlas.glyphs;
        if (glyphPtr !is null)
        {
            const glyph = *glyphPtr;
            const advance = glyph.advance > 0.0f ? glyph.advance : atlas.pixelHeight * 0.6f;
            const left = cursorX + glyph.bearingX;
            const right = left + glyph.width;

            if (!lineHasGlyph)
            {
                lineLeft = left;
                lineRight = right;
                lineHasGlyph = true;
            }
            else
            {
                lineLeft = lineLeft < left ? lineLeft : left;
                lineRight = lineRight > right ? lineRight : right;
            }

            cursorX += advance;
        }
        else if (auto fallbackPtr = '?' in atlas.glyphs)
        {
            const glyph = *fallbackPtr;
            const advance = glyph.advance > 0.0f ? glyph.advance : atlas.pixelHeight * 0.6f;
            const left = cursorX + glyph.bearingX;
            const right = left + glyph.width;

            if (!lineHasGlyph)
            {
                lineLeft = left;
                lineRight = right;
                lineHasGlyph = true;
            }
            else
            {
                lineLeft = lineLeft < left ? lineLeft : left;
                lineRight = lineRight > right ? lineRight : right;
            }

            cursorX += advance;
        }
        else
        {
            cursorX += atlas.pixelHeight * 0.6f;
        }

        previousChar = ch;
    }

    const renderedLeft = lineLeft < 0.0f ? lineLeft : 0.0f;
    const renderedRight = lineRight > cursorX ? lineRight : cursorX;
    const lineWidth = renderedRight - renderedLeft;
    logLineVerbose("measureTextWidth final line ", lineCount, ": width=", lineWidth, ", text chars=", text.length);
    logLineVerbose("measureTextWidth result: widestWidth=", (lineWidth > widestWidth ? lineWidth : widestWidth), ", lines=", text.length == 0 ? 0 : lineCount);
    return lineWidth > widestWidth ? lineWidth : widestWidth;
}

/** Appends text quads using the texture coordinates stored in a font atlas.
 *
 * The UI layer passes the current vertex list and a depth value so text can be
 * layered with the rest of the retained widgets and the HUD overlay.
 *
 * Params:
 *   vertices = Destination vertex list.
 *   atlas = Font atlas used for the text.
 *   text = Text to append.
 *   x = Starting x position in pixels.
 *   y = Starting y position in pixels.
 *   color = Text color in RGBA format.
 *   extentWidth = Swapchain width in pixels.
 *   extentHeight = Swapchain height in pixels.
 *
 * Returns:
 *   Nothing.
 */
void appendText(ref Vertex[] vertices, const(FontAtlas) atlas, string text, float x, float y, float z, float[4] color, float extentWidth, float extentHeight)
{
    float cursorX = x;
    float cursorY = y;
    const baselineOffset = atlas.ascent;
    dchar previousChar = '\0';
    const vertexCountBefore = vertices.length;

    logLineVerbose("appendText: text chars=", text.length, ", start=", x, ",", y, ", baselineOffset=", baselineOffset, ", atlas=", atlas.width, "x", atlas.height);

    foreach (ch; text)
    {
        if (ch == '\n')
        {
            cursorX = x;
            cursorY += atlas.lineHeight;
            previousChar = '\0';
            continue;
        }

        if (previousChar != '\0')
        {
            const leftKerningPtr = previousChar in atlas.kerning;
            if (leftKerningPtr !is null)
            {
                const kerningPtr = ch in *leftKerningPtr;
                if (kerningPtr !is null)
                    cursorX += *kerningPtr;
            }
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
        previousChar = ch;
    }

    logLineVerbose("appendText: emitted vertices=", vertices.length - vertexCountBefore, ", quads=", (vertices.length - vertexCountBefore) / 6, ", final cursor=", cursorX, ",", cursorY);
}

/** Pixel-space bounds of rendered text geometry. */
private struct RenderBounds
{
    float width; /// Width in pixels.
    float height; /// Height in pixels.
}

/** Measures the pixel-space bounds of vertices emitted by appendText().
 *
 * Params:
 *   vertices = Text geometry to inspect.
 *   extentWidth = Swapchain width used to convert NDC back to pixels.
 *   extentHeight = Swapchain height used to convert NDC back to pixels.
 *
 * Returns:
 *   The measured bounds of the emitted quad vertices.
 */
private RenderBounds measureRenderedBounds(const(Vertex)[] vertices, float extentWidth, float extentHeight)
{
    RenderBounds bounds;

    if (vertices.length == 0)
        return bounds;

    float left = 0.0f;
    float right = 0.0f;
    float top = 0.0f;
    float bottom = 0.0f;
    bool first = true;

    foreach (vertex; vertices)
    {
        const pixelX = (vertex.position[0] + 1.0f) * 0.5f * extentWidth;
        const pixelY = (vertex.position[1] + 1.0f) * 0.5f * extentHeight;

        if (first)
        {
            left = pixelX;
            right = pixelX;
            top = pixelY;
            bottom = pixelY;
            first = false;
        }
        else
        {
            if (pixelX < left)
                left = pixelX;
            if (pixelX > right)
                right = pixelX;
            if (pixelY < top)
                top = pixelY;
            if (pixelY > bottom)
                bottom = pixelY;
        }
    }

    bounds.width = right - left;
    bounds.height = bottom - top;
    return bounds;
}

/** Copies one FreeType bitmap into the atlas pixel buffer.
 *
 * Params:
 *   atlasPixels = RGBA destination pixels for the atlas.
 *   atlasWidth = Atlas width in pixels.
 *   atlasHeight = Atlas height in pixels.
 *   atlasX = Left edge of the glyph cell in pixels.
 *   atlasY = Top edge of the glyph cell in pixels.
 *   bitmap = FreeType bitmap to copy.
 *
 * Returns:
 *   Nothing.
 */
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

/** Appends a textured quad in normalized device coordinates.
 *
 * Params:
 *   vertices = Destination vertex list.
 *   left = Left edge in pixel space.
 *   top = Top edge in pixel space.
 *   right = Right edge in pixel space.
 *   bottom = Bottom edge in pixel space.
 *   z = Depth value for the quad.
 *   u0 = Minimum texture U coordinate.
 *   v0 = Minimum texture V coordinate.
 *   u1 = Maximum texture U coordinate.
 *   v1 = Maximum texture V coordinate.
 *   color = Vertex color in RGBA format.
 *   extentWidth = Swapchain width used for NDC conversion.
 *   extentHeight = Swapchain height used for NDC conversion.
 *
 * Returns:
 *   Nothing.
 */
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

@("default glyph set includes fallback characters")
unittest
{
    assert(indexOf(defaultGlyphSet, '?') >= 0);
    assert(indexOf(defaultGlyphSet, ' ') >= 0);
    assert(selectDefaultFontPath().length > 0);
}

@("collect glyph set keeps first-seen order")
unittest
{
    // This is the first educational safety net: translate texts into a unique
    // glyph corpus before asking FreeType to build any atlas.
    auto glyphSet = collectGlyphSet(["Hello", "World", "Glyphs"]);
    assert(indexOf(glyphSet, 'H') >= 0);
    assert(indexOf(glyphSet, 'W') >= 0);
    assert(indexOf(glyphSet, 'l') >= 0);
    assert(indexOf(glyphSet, ' ') >= 0);
    assert(indexOf(glyphSet, '?') >= 0);
}

@("font atlas exposes usable metrics")
unittest
{
    // The atlas must expose sane metrics for the renderer and the UI layout.
    const fontPath = selectDefaultFontPath();
    auto atlas = buildFontAtlas(fontPath, 18, collectGlyphSet(["STATUS", "Render Modes"]));

    assert(atlas.pixelHeight == 18);
    assert(atlas.width > 0);
    assert(atlas.height > 0);
    assert(atlas.ascent > 0.0f);
    assert(atlas.descent > 0.0f);
    assert(atlas.lineHeight > 0.0f);
    assert(('S' in atlas.glyphs) !is null);
    assert((' ' in atlas.glyphs) !is null);
    assert(('?' in atlas.glyphs) !is null);
}

@("single glyph width matches emitted quad")
unittest
{
    // The width calculation must match the actual quads emitted by appendText().
    const fontPath = selectDefaultFontPath();
    auto atlas = buildFontAtlas(fontPath, 20, collectGlyphSet(["A", "V", "Hello", "To"]));

    Vertex[] vertices;
    appendText(vertices, atlas, "A", 20.0f, 40.0f, 0.0f, [1.0f, 1.0f, 1.0f, 1.0f], 1000.0f, 1000.0f);

    const measuredWidth = measureTextWidth(atlas, "A");
    const renderedBounds = measureRenderedBounds(vertices, 1000.0f, 1000.0f);
    assert(abs(measuredWidth - renderedBounds.width) <= 0.75f, format("measured width %s should match rendered width %s", measuredWidth, renderedBounds.width));
    assert(renderedBounds.width > 0.0f);
}

@("kerning affects paired width")
unittest
{
    // The pair width must include the atlas kerning adjustment, not just the
    // sum of the two isolated glyph advances.
    const fontPath = selectDefaultFontPath();
    auto atlas = buildFontAtlas(fontPath, 20, collectGlyphSet(["AV", "To", "Hello"]));

    const singleAWidth = measureTextWidth(atlas, "A");
    const singleVWidth = measureTextWidth(atlas, "V");
    const pairWidth = measureTextWidth(atlas, "AV");

    Vertex[] vertices;
    appendText(vertices, atlas, "AV", 20.0f, 40.0f, 0.0f, [1.0f, 1.0f, 1.0f, 1.0f], 1000.0f, 1000.0f);

    const renderedBounds = measureRenderedBounds(vertices, 1000.0f, 1000.0f);
    assert(abs(pairWidth - renderedBounds.width) <= 0.75f, format("measured width %s should match rendered width %s", pairWidth, renderedBounds.width));
    assert(pairWidth <= singleAWidth + singleVWidth + 0.75f, format("kerning pair width %s should not exceed isolated widths %s + %s", pairWidth, singleAWidth, singleVWidth));

    const leftKerningPtr = 'A' in atlas.kerning;
    if (leftKerningPtr !is null)
    {
        const kerningPtr = 'V' in *leftKerningPtr;
        if (kerningPtr !is null)
            assert(pairWidth < singleAWidth + singleVWidth, format("kerning should reduce the pair width: %s < %s + %s", pairWidth, singleAWidth, singleVWidth));
    }
}

@("multiline text uses widest line")
unittest
{
    // Multi-line input must use the widest line for width and the line height for height.
    const fontPath = selectDefaultFontPath();
    auto atlas = buildFontAtlas(fontPath, 18, collectGlyphSet(["Line one", "A much wider second line"]));

    Vertex[] vertices;
    appendText(vertices, atlas, "Hi\nThere", 15.0f, 30.0f, 0.0f, [1.0f, 1.0f, 1.0f, 1.0f], 1000.0f, 1000.0f);

    const measuredWidth = measureTextWidth(atlas, "Hi\nThere");
    const firstLineWidth = measureTextWidth(atlas, "Hi");
    const secondLineWidth = measureTextWidth(atlas, "There");
    const renderedBounds = measureRenderedBounds(vertices, 1000.0f, 1000.0f);
    assert(measuredWidth >= firstLineWidth);
    assert(measuredWidth >= secondLineWidth);
    assert(abs(measuredWidth - renderedBounds.width) <= 0.75f, format("measured width %s should match rendered width %s", measuredWidth, renderedBounds.width));
    assert(renderedBounds.height >= atlas.lineHeight, format("rendered multiline height %s should be at least one line height %s", renderedBounds.height, atlas.lineHeight));
}