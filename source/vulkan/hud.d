module vulkan.hud;

import std.format : format;
import std.math : PI;

import vulkan.pipeline : Vertex;

Vertex[] buildHudOverlayVertices(float extentWidth, float extentHeight, float fps, float yawAngle, float pitchAngle)
{
    Vertex[] vertices;

    const panelLeft = 18.0f;
    const panelTop = 18.0f;
    const panelRight = extentWidth > 454.0f ? 454.0f : extentWidth - 18.0f;
    const panelBottom = extentHeight > 246.0f ? 246.0f : extentHeight - 18.0f;

    if (panelRight > panelLeft && panelBottom > panelTop)
    {
        appendRect(vertices, panelLeft, panelTop, panelRight, panelBottom, 0.0f, [0.06f, 0.08f, 0.11f], extentWidth, extentHeight);
        appendRect(vertices, panelLeft, panelTop, panelRight, panelTop + 6.0f, 0.0f, [0.20f, 0.48f, 0.88f], extentWidth, extentHeight);
    }

    appendText(vertices, "HUD TEST", 32.0f, 34.0f, 6.0f, [0.96f, 0.72f, 0.18f], extentWidth, extentHeight);
    appendText(vertices, format("FPS %.0f", fps), 34.0f, 96.0f, 4.0f, [0.95f, 0.95f, 0.95f], extentWidth, extentHeight);
    appendText(vertices, format("YAW %.1f", yawAngle * 180.0f / cast(float)PI), 34.0f, 142.0f, 5.0f, [0.40f, 0.92f, 0.58f], extentWidth, extentHeight);
    appendText(vertices, format("PITCH %.1f", pitchAngle * 180.0f / cast(float)PI), 34.0f, 190.0f, 5.0f, [0.38f, 0.80f, 0.98f], extentWidth, extentHeight);

    return vertices;
}

private void appendText(ref Vertex[] vertices, string text, float x, float y, float scale, float[3] color, float extentWidth, float extentHeight)
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

private void appendGlyph(ref Vertex[] vertices, char ch, float x, float y, float scale, float[3] color, float extentWidth, float extentHeight)
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

private void appendRect(ref Vertex[] vertices, float left, float top, float right, float bottom, float z, float[3] color, float extentWidth, float extentHeight)
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

private float toNdcX(float pixelX, float extentWidth)
{
    return pixelX / extentWidth * 2.0f - 1.0f;
}

private float toNdcY(float pixelY, float extentHeight)
{
    return pixelY / extentHeight * 2.0f - 1.0f;
}

private ubyte[7] glyphRows(char ch)
{
    switch (ch)
    {
        case ' ':
            return [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];
        case '.':
            return [0x00, 0x00, 0x00, 0x00, 0x00, 0x06, 0x06];
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
        case 'C':
            return [0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E];
        case 'D':
            return [0x1E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x1E];
        case 'E':
            return [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F];
        case 'F':
            return [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10];
        case 'H':
            return [0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11];
        case 'I':
            return [0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E];
        case 'K':
            return [0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11];
        case 'L':
            return [0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F];
        case 'N':
            return [0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11];
        case 'O':
            return [0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E];
        case 'P':
            return [0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10];
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
        case 'Y':
            return [0x11, 0x11, 0x0A, 0x04, 0x04, 0x04, 0x04];
        default:
            return [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];
    }
}