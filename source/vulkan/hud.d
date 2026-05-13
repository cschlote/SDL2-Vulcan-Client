/** $purposeofFile
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.hud;

import std.format : format;
import std.math : PI;

import vulkan.font : FontAtlas, appendText;
import vulkan.pipeline : Vertex;

/** Holds the panel and text geometry for the HUD overlay.
 */
struct HudOverlayGeometry
{
    /** Window body and header quads. */
    Vertex[] panels;
    /** Small-body text quads. */
    Vertex[] smallText;
    /** Medium-body text quads. */
    Vertex[] mediumText;
    /** Large sample text quads. */
    Vertex[] largeText;
}

/** Builds the HUD overlay geometry for the current frame.
 *
 * @param extentWidth = Swapchain width in pixels.
 * @param extentHeight = Swapchain height in pixels.
 * @param fps = Last measured frame rate.
 * @param yawAngle = Current yaw angle in radians.
 * @param pitchAngle = Current pitch angle in radians.
 * @param shapeName = Name of the active polyhedron.
 * @param renderModeName = Name of the active render mode.
 * @param smallFont = Font atlas used for 12 px body copy.
 * @param mediumFont = Font atlas used for 18 px labels and titles.
 * @param largeFont = Font atlas used for 24 px comparison samples.
 * @returns Panel and text vertex lists that can be uploaded to the GPU.
 */
HudOverlayGeometry buildHudOverlayVertices(float extentWidth, float extentHeight, float fps, float yawAngle, float pitchAngle, string shapeName, string renderModeName, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont, ref const(FontAtlas) largeFont)
{
    HudOverlayGeometry geometry;

    const float margin = 18.0f;

    appendWindow(geometry.panels, margin, margin, extentWidth - margin < 612.0f ? extentWidth - margin : 612.0f, extentHeight - margin < 256.0f ? extentHeight - margin : 256.0f, extentWidth, extentHeight, [0.06f, 0.08f, 0.11f, 0.58f], [0.20f, 0.48f, 0.88f, 0.90f]);
    appendWindow(geometry.panels, margin, 272.0f, extentWidth - margin < 352.0f ? extentWidth - margin : 352.0f, extentHeight - margin < 470.0f ? extentHeight - margin : 470.0f, extentWidth, extentHeight, [0.06f, 0.08f, 0.11f, 0.56f], [0.20f, 0.48f, 0.88f, 0.86f]);
    appendWindow(geometry.panels, 366.0f, 272.0f, extentWidth - margin < 632.0f ? extentWidth - margin : 632.0f, extentHeight - margin < 470.0f ? extentHeight - margin : 470.0f, extentWidth, extentHeight, [0.06f, 0.08f, 0.11f, 0.50f], [0.20f, 0.48f, 0.88f, 0.80f]);

    appendText(geometry.mediumText, mediumFont, "DESKTOP OVERLAY", 30.0f, 24.0f, [0.96f, 0.72f, 0.18f, 0.96f], extentWidth, extentHeight);
    appendText(geometry.smallText, smallFont, "NATIVE WINDOW PIXELS. REAL FREE-TYPE FONTS AT 12, 18, AND 24 PX.", 34.0f, 58.0f, [0.86f, 0.90f, 0.94f, 0.92f], extentWidth, extentHeight);
    appendText(geometry.mediumText, mediumFont, format("FRAME RATE: %.0f FRAMES PER SECOND", fps), 36.0f, 94.0f, [0.95f, 0.95f, 0.95f, 0.92f], extentWidth, extentHeight);
    appendText(geometry.smallText, smallFont, format("CAMERA YAW: %.1f DEGREES", yawAngle * 180.0f / cast(float)PI), 36.0f, 128.0f, [0.40f, 0.92f, 0.58f, 0.92f], extentWidth, extentHeight);
    appendText(geometry.smallText, smallFont, format("CAMERA PITCH: %.1f DEGREES", pitchAngle * 180.0f / cast(float)PI), 36.0f, 150.0f, [0.38f, 0.80f, 0.98f, 0.92f], extentWidth, extentHeight);
    appendText(geometry.smallText, smallFont, format("ACTIVE SHAPE: %s", shapeName), 36.0f, 174.0f, [0.94f, 0.94f, 0.94f, 0.92f], extentWidth, extentHeight);
    appendText(geometry.smallText, smallFont, format("CURRENT MODE: %s", renderModeName), 36.0f, 196.0f, [0.94f, 0.82f, 0.40f, 0.92f], extentWidth, extentHeight);

    appendText(geometry.mediumText, mediumFont, "RENDER MODES", 30.0f, 278.0f, [0.96f, 0.72f, 0.18f, 0.96f], extentWidth, extentHeight);
    appendText(geometry.smallText, smallFont, "F  FLAT COLOR RENDERING", 36.0f, 308.0f, [0.98f, 0.86f, 0.40f, 0.92f], extentWidth, extentHeight);
    appendText(geometry.smallText, smallFont, "T  LIT AND TEXTURED RENDERING", 36.0f, 332.0f, [0.98f, 0.86f, 0.40f, 0.92f], extentWidth, extentHeight);
    appendText(geometry.smallText, smallFont, "W  WIREFRAME RENDERING", 36.0f, 356.0f, [0.98f, 0.86f, 0.40f, 0.92f], extentWidth, extentHeight);
    appendText(geometry.smallText, smallFont, "H  HIDDEN LINE RENDERING", 36.0f, 380.0f, [0.98f, 0.86f, 0.40f, 0.92f], extentWidth, extentHeight);
    appendText(geometry.smallText, smallFont, "+ / -  SWITCH SHAPE", 36.0f, 406.0f, [0.95f, 0.95f, 0.95f, 0.92f], extentWidth, extentHeight);
    appendText(geometry.smallText, smallFont, "ARROWS  ROTATE CAMERA", 36.0f, 430.0f, [0.95f, 0.95f, 0.95f, 0.92f], extentWidth, extentHeight);
    appendText(geometry.smallText, smallFont, "ESC  CLOSE APPLICATION", 36.0f, 454.0f, [0.95f, 0.95f, 0.95f, 0.92f], extentWidth, extentHeight);

    appendText(geometry.mediumText, mediumFont, "FONT SIZES", 396.0f, 278.0f, [0.96f, 0.72f, 0.18f, 0.96f], extentWidth, extentHeight);
    appendText(geometry.smallText, smallFont, "12 PX  THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG.", 396.0f, 308.0f, [0.95f, 0.95f, 0.95f, 0.92f], extentWidth, extentHeight);
    appendText(geometry.mediumText, mediumFont, "18 PX  THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG.", 396.0f, 342.0f, [0.95f, 0.95f, 0.95f, 0.92f], extentWidth, extentHeight);
    appendText(geometry.largeText, largeFont, "24 PX  THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG.", 396.0f, 388.0f, [0.95f, 0.95f, 0.95f, 0.92f], extentWidth, extentHeight);
    appendText(geometry.smallText, smallFont, "REAL FONTS RENDER EACH SIZE AS ITS OWN ATLAS, NOT AS A SCALE OF A SMALLER BITMAP.", 396.0f, 432.0f, [0.86f, 0.90f, 0.94f, 0.92f], extentWidth, extentHeight);

    return geometry;
}

/** Appends a translucent UI window frame with a title bar.
 *
 * @param vertices = Destination vertex list.
 * @param left = Left edge in pixels.
 * @param top = Top edge in pixels.
 * @param right = Right edge in pixels.
 * @param bottom = Bottom edge in pixels.
 * @param extentWidth = Swapchain width in pixels.
 * @param extentHeight = Swapchain height in pixels.
 * @param bodyColor = Window body color in RGBA format.
 * @param headerColor = Window header color in RGBA format.
 * @returns Nothing.
 */
private void appendWindow(ref Vertex[] vertices, float left, float top, float right, float bottom, float extentWidth, float extentHeight, float[4] bodyColor, float[4] headerColor)
{
    if (right <= left || bottom <= top)
        return;

    appendRect(vertices, left, top, right, bottom, 0.0f, bodyColor, extentWidth, extentHeight);
    appendRect(vertices, left, top, right, top + 7.0f, 0.0f, headerColor, extentWidth, extentHeight);
    appendRect(vertices, left, top, right, top + 1.0f, 0.01f, [0.98f, 0.98f, 1.0f, 0.46f], extentWidth, extentHeight);
    appendRect(vertices, left, bottom - 1.0f, right, bottom, 0.01f, [0.98f, 0.98f, 1.0f, 0.26f], extentWidth, extentHeight);
    appendRect(vertices, left, top, left + 1.0f, bottom, 0.01f, [0.98f, 0.98f, 1.0f, 0.26f], extentWidth, extentHeight);
    appendRect(vertices, right - 1.0f, top, right, bottom, 0.01f, [0.98f, 0.98f, 1.0f, 0.26f], extentWidth, extentHeight);
}

/** Renders a text string as a sequence of glyph quads.
 *
 * @param vertices = Destination vertex list.
 * @param text = Text to append.
 * @param x = Starting x position in pixels.
 * @param y = Starting y position in pixels.
 * @param scale = Glyph cell size in pixels.
 * @param color = Glyph color in RGBA format.
 * @param extentWidth = Swapchain width in pixels.
 * @param extentHeight = Swapchain height in pixels.
 * @returns Nothing.
 */
private void appendText(ref Vertex[] vertices, string text, float x, float y, float scale, float[4] color, float extentWidth, float extentHeight)
{
    float cursorX = x;
    const advance = scale * 6.0f;

    foreach (ch; text)
    {
        if (ch == ' ')
        {
            cursorX += advance;
            continue;
        }

        appendGlyph(vertices, ch, cursorX, y, scale, color, extentWidth, extentHeight);
        cursorX += advance;
    }
}

/** Renders a single glyph as a grid of rectangles.
 *
 * @param vertices = Destination vertex list.
 * @param ch = Glyph character.
 * @param x = Starting x position in pixels.
 * @param y = Starting y position in pixels.
 * @param scale = Glyph cell size in pixels.
 * @param color = Glyph color in RGBA format.
 * @param extentWidth = Swapchain width in pixels.
 * @param extentHeight = Swapchain height in pixels.
 * @returns Nothing.
 */
private void appendGlyph(ref Vertex[] vertices, char ch, float x, float y, float scale, float[4] color, float extentWidth, float extentHeight)
{
    const rows = glyphRows(ch);

    foreach (rowIndex; 0 .. rows.length)
    {
        foreach (columnIndex; 0 .. 5)
        {
            const mask = cast(ubyte)(1 << (4 - columnIndex));
            if ((rows[rowIndex] & mask) == 0)
                continue;

            const cellX = x + cast(float)columnIndex * scale;
            const cellY = y + cast(float)rowIndex * scale;
            appendRect(vertices, cellX, cellY, cellX + scale, cellY + scale, 0.0f, color, extentWidth, extentHeight);
        }
    }
}

/** Appends a solid rectangle as two triangles in NDC coordinates.
 *
 * @param vertices = Destination vertex list.
 * @param left = Left edge in pixels.
 * @param top = Top edge in pixels.
 * @param right = Right edge in pixels.
 * @param bottom = Bottom edge in pixels.
 * @param z = Depth value in clip space.
 * @param color = Rectangle color in RGBA format.
 * @param extentWidth = Swapchain width in pixels.
 * @param extentHeight = Swapchain height in pixels.
 * @returns Nothing.
 */
private void appendRect(ref Vertex[] vertices, float left, float top, float right, float bottom, float z, float[4] color, float extentWidth, float extentHeight)
{
    const x0 = toNdcX(left, extentWidth);
    const y0 = toNdcY(top, extentHeight);
    const x1 = toNdcX(right, extentWidth);
    const y1 = toNdcY(bottom, extentHeight);

    vertices ~= Vertex([x0, y0, z], color);
    vertices ~= Vertex([x1, y0, z], color);
    vertices ~= Vertex([x1, y1, z], color);

    vertices ~= Vertex([x0, y0, z], color);
    vertices ~= Vertex([x1, y1, z], color);
    vertices ~= Vertex([x0, y1, z], color);
}

/** Converts a pixel x coordinate into normalized device coordinates.
 *
 * @param pixelX = X coordinate in pixels.
 * @param extentWidth = Swapchain width in pixels.
 * @returns X in NDC space.
 */
private float toNdcX(float pixelX, float extentWidth)
{
    return pixelX / extentWidth * 2.0f - 1.0f;
}

/** Converts a pixel y coordinate into normalized device coordinates.
 *
 * @param pixelY = Y coordinate in pixels.
 * @param extentHeight = Swapchain height in pixels.
 * @returns Y in NDC space.
 */
private float toNdcY(float pixelY, float extentHeight)
{
    return pixelY / extentHeight * 2.0f - 1.0f;
}

/** Returns a seven-row, five-column bitmap for the requested glyph.
 *
 * @param ch = Glyph character.
 * @returns A compact bitmap representation of the glyph.
 */
private ubyte[7] glyphRows(char ch)
{
    switch (ch)
    {
        case ' ':
            return [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];
        case '.':
            return [0x00, 0x00, 0x00, 0x00, 0x00, 0x06, 0x06];
        case '+':
            return [0x00, 0x04, 0x04, 0x1F, 0x04, 0x04, 0x00];
        case '-':
            return [0x00, 0x00, 0x00, 0x1F, 0x00, 0x00, 0x00];
        case '/':
            return [0x01, 0x02, 0x04, 0x08, 0x10, 0x00, 0x00];
        case '0':
            return [0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E];
        case '1':
            return [0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E];
        case '2':
            return [0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F];
        case '3':
            return [0x1E, 0x01, 0x01, 0x0E, 0x01, 0x01, 0x1E];
        case '4':
            return [0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02];
        case '5':
            return [0x1F, 0x10, 0x10, 0x1E, 0x01, 0x01, 0x1E];
        case '6':
            return [0x0E, 0x10, 0x10, 0x1E, 0x11, 0x11, 0x0E];
        case '7':
            return [0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08];
        case '8':
            return [0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E];
        case '9':
            return [0x0E, 0x11, 0x11, 0x0F, 0x01, 0x01, 0x0E];
        case 'A':
            return [0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11];
        case 'B':
            return [0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E];
        case 'C':
            return [0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E];
        case 'D':
            return [0x1E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x1E];
        case 'E':
            return [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F];
        case 'F':
            return [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10];
        case 'G':
            return [0x0E, 0x11, 0x10, 0x10, 0x13, 0x11, 0x0E];
        case 'H':
            return [0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11];
        case 'I':
            return [0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E];
        case 'J':
            return [0x1F, 0x02, 0x02, 0x02, 0x12, 0x12, 0x0C];
        case 'K':
            return [0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11];
        case 'L':
            return [0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F];
        case 'M':
            return [0x11, 0x1B, 0x15, 0x11, 0x11, 0x11, 0x11];
        case 'N':
            return [0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11];
        case 'O':
            return [0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E];
        case 'P':
            return [0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10];
        case 'Q':
            return [0x0E, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0D];
        case 'R':
            return [0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11];
        case 'S':
            return [0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E];
        case 'T':
            return [0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04];
        case 'U':
            return [0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E];
        case 'V':
            return [0x11, 0x11, 0x11, 0x11, 0x0A, 0x0A, 0x04];
        case 'W':
            return [0x11, 0x11, 0x11, 0x15, 0x15, 0x1B, 0x11];
        case 'X':
            return [0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11];
        case 'Y':
            return [0x11, 0x11, 0x0A, 0x04, 0x04, 0x04, 0x04];
        case 'Z':
            return [0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F];
        default:
            return [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];
    }
}