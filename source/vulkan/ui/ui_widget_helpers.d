/** Helper functions shared by retained UI widgets.
 *
 * These helpers keep the widget classes small and focused on layout and tree
 * structure while the low-level quad and text emission stays in one place.
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.ui.ui_widget_helpers;

import std.algorithm : max, min;
import std.math : isInfinity, isNaN;

import vulkan.font.font_legacy : appendText;
import vulkan.engine.pipeline : Vertex;
import vulkan.ui.ui_context : UiRenderContext, UiTextStyle;
import vulkan.ui.ui_geometry : UiImageDrawCommand;

/** Appends a generic surface fill with an optional border. */
void appendSurfaceFrame(ref UiRenderContext context, float left, float top, float right, float bottom, float[4] backgroundColor, float[4] borderColor, float z, bool drawBackground = true, bool drawBorder = true)
{
    if (right <= left || bottom <= top)
        return;

    if (drawBackground)
        appendQuad(context, left, top, right, bottom, z, backgroundColor);

    if (drawBorder)
    {
        appendQuad(context, left, top, right, top + 1.0f, z - 0.001f, borderColor);
        appendQuad(context, left, bottom - 1.0f, right, bottom, z - 0.001f, borderColor);
        appendQuad(context, left, top, left + 1.0f, bottom, z - 0.001f, borderColor);
        appendQuad(context, right - 1.0f, top, right, bottom, z - 0.001f, borderColor);
    }
}

/** Appends one texture-backed image draw intent with local widget coordinates. */
void appendImageQuad(ref UiRenderContext context, string assetId, float left, float top, float right, float bottom, float z, float[4] tintColor, float[4] fallbackColor, float[4] uvRect)
{
    if (context.images is null || assetId.length == 0 || right <= left || bottom <= top)
        return;

    float clippedLeft = context.originX + left;
    float clippedTop = context.originY + top;
    float clippedRight = context.originX + right;
    float clippedBottom = context.originY + bottom;
    float clippedU0 = uvRect[0];
    float clippedV0 = uvRect[1];
    float clippedU1 = uvRect[2];
    float clippedV1 = uvRect[3];

    if (context.clipEnabled)
    {
        const originalLeft = clippedLeft;
        const originalTop = clippedTop;
        const originalRight = clippedRight;
        const originalBottom = clippedBottom;
        clippedLeft = max(clippedLeft, context.clipLeft);
        clippedTop = max(clippedTop, context.clipTop);
        clippedRight = min(clippedRight, context.clipRight);
        clippedBottom = min(clippedBottom, context.clipBottom);
        if (clippedRight <= clippedLeft || clippedBottom <= clippedTop)
            return;

        const originalWidth = originalRight - originalLeft;
        const originalHeight = originalBottom - originalTop;
        const uSpan = uvRect[2] - uvRect[0];
        const vSpan = uvRect[3] - uvRect[1];
        clippedU0 = uvRect[0] + uSpan * ((clippedLeft - originalLeft) / originalWidth);
        clippedU1 = uvRect[0] + uSpan * ((clippedRight - originalLeft) / originalWidth);
        clippedV0 = uvRect[1] + vSpan * ((clippedTop - originalTop) / originalHeight);
        clippedV1 = uvRect[1] + vSpan * ((clippedBottom - originalTop) / originalHeight);
    }

    UiImageDrawCommand command;
    command.assetId = assetId;
    command.fallbackColor = fallbackColor;

    const x0 = absoluteToNdcX(context, clippedLeft);
    const y0 = absoluteToNdcY(context, clippedTop);
    const x1 = absoluteToNdcX(context, clippedRight);
    const y1 = absoluteToNdcY(context, clippedBottom);
    const u0 = clippedU0;
    const v0 = clippedV0;
    const u1 = clippedU1;
    const v1 = clippedV1;

    command.vertices[0] = Vertex([x0, y0, z], tintColor, [0.0f, 0.0f, 1.0f], [u0, v0]);
    command.vertices[1] = Vertex([x1, y0, z], tintColor, [0.0f, 0.0f, 1.0f], [u1, v0]);
    command.vertices[2] = Vertex([x1, y1, z], tintColor, [0.0f, 0.0f, 1.0f], [u1, v1]);
    command.vertices[3] = Vertex([x0, y0, z], tintColor, [0.0f, 0.0f, 1.0f], [u0, v0]);
    command.vertices[4] = Vertex([x1, y1, z], tintColor, [0.0f, 0.0f, 1.0f], [u1, v1]);
    command.vertices[5] = Vertex([x0, y1, z], tintColor, [0.0f, 0.0f, 1.0f], [u0, v1]);

    (*context.images) ~= command;
}

/** Appends the body and header quads for a retained window frame.
 *
 * The header fill can reserve horizontal insets so the decorative surface
 * stays clear of close buttons, resize grips, and header extras.
 */
void appendWindowFrame(ref UiRenderContext context, float left, float top, float right, float bottom, float headerHeight, float[4] bodyColor, float[4] headerColor, float z, float headerLeftInset = 0.0f, float headerRightInset = 0.0f)
{
    if (right <= left || bottom <= top)
        return;

    if (headerHeight <= 0.0f)
    {
        appendQuad(context, left, top, right, bottom, z, bodyColor);
        return;
    }

    const effectiveHeaderHeight = headerHeight < bottom - top ? headerHeight : bottom - top;
    const headerBottom = top + effectiveHeaderHeight;
    if (headerBottom < bottom)
        appendQuad(context, left, headerBottom, right, bottom, z, bodyColor);

    const headerLeft = left + headerLeftInset;
    const headerRight = right - headerRightInset;
    if (headerLeft > left)
        appendQuad(context, left, top, headerLeft, headerBottom, z, bodyColor);
    if (headerRight < right)
        appendQuad(context, headerRight, top, right, headerBottom, z, bodyColor);
    if (headerRight > headerLeft)
        appendQuad(context, headerLeft, top, headerRight, headerBottom, z - 0.001f, headerColor);

    appendQuad(context, left, headerBottom - 2.0f, right, headerBottom - 1.0f, z - 0.002f, [0.10f, 0.10f, 0.12f, 0.70f]);
    appendQuad(context, left, headerBottom - 1.0f, right, headerBottom, z - 0.002f, [0.98f, 0.98f, 1.0f, 0.48f]);
}

/** Appends the outer border quads for a retained window frame. */
void appendWindowBorder(ref UiRenderContext context, float left, float top, float right, float bottom, float z, float thickness = 1.0f)
{
    if (right <= left || bottom <= top || thickness <= 0.0f)
        return;

    const clampedThickness = thickness < (right - left) * 0.5f ? thickness : (right - left) * 0.5f;
    const verticalThickness = clampedThickness < (bottom - top) * 0.5f ? clampedThickness : (bottom - top) * 0.5f;
    appendQuad(context, left, top, right, top + verticalThickness, z - 0.002f, [0.98f, 0.98f, 1.0f, 0.34f]);
    appendQuad(context, left, bottom - verticalThickness, right, bottom, z - 0.002f, [0.98f, 0.98f, 1.0f, 0.26f]);
    appendQuad(context, left, top, left + clampedThickness, bottom, z - 0.002f, [0.98f, 0.98f, 1.0f, 0.26f]);
    appendQuad(context, right - clampedThickness, top, right, bottom, z - 0.002f, [0.98f, 0.98f, 1.0f, 0.26f]);
}

/** Appends the button body and border quads for the retained UI style. */
void appendButtonFrame(ref UiRenderContext context, float left, float top, float right, float bottom, float[4] bodyColor, float[4] borderColor, float z)
{
    if (right <= left || bottom <= top)
        return;

    appendQuad(context, left, top, right, bottom, z, bodyColor);
    appendQuad(context, left, top, right, top + 1.0f, z - 0.001f, [1.0f, 1.0f, 1.0f, 0.24f]);
    appendQuad(context, left, bottom - 1.0f, right, bottom, z - 0.001f, [0.0f, 0.0f, 0.0f, 0.34f]);
    appendQuad(context, left, top, left + 1.0f, bottom, z - 0.001f, borderColor);
    appendQuad(context, right - 1.0f, top, right, bottom, z - 0.001f, borderColor);
}

/** Emits a single text line for the requested style at the local widget offset. */
void appendTextLine(ref UiRenderContext context, UiTextStyle style, string text, float x, float y, float[4] color, float z)
{
    const atlas = context.atlasFor(style);
    auto vertices = textVerticesFor(context, style);

    if (atlas is null || vertices is null)
        return;

    if (!context.clipEnabled)
    {
        appendText(*vertices, *atlas, text, context.originX + x, context.originY + y, z, color, context.extentWidth, context.extentHeight);
        return;
    }

    Vertex[] emitted;
    appendText(emitted, *atlas, text, context.originX + x, context.originY + y, z, color, context.extentWidth, context.extentHeight);
    foreach (index; 0 .. emitted.length / 6)
        appendClippedTexturedQuad(context, *vertices, emitted[index * 6 .. index * 6 + 6]);
}

/** Returns the active vertex buffer for the requested text style. */
Vertex[]* textVerticesFor(ref UiRenderContext context, UiTextStyle style)
{
    return context.textVerticesFor(style);
}

/** Appends a colored quad to the panel vertex buffer in normalized device space. */
void appendQuad(ref UiRenderContext context, float left, float top, float right, float bottom, float z, float[4] color)
{
    float clippedLeft = context.originX + left;
    float clippedTop = context.originY + top;
    float clippedRight = context.originX + right;
    float clippedBottom = context.originY + bottom;

    if (context.clipEnabled)
    {
        clippedLeft = max(clippedLeft, context.clipLeft);
        clippedTop = max(clippedTop, context.clipTop);
        clippedRight = min(clippedRight, context.clipRight);
        clippedBottom = min(clippedBottom, context.clipBottom);
        if (clippedRight <= clippedLeft || clippedBottom <= clippedTop)
            return;
    }

    const x0 = absoluteToNdcX(context, clippedLeft);
    const y0 = absoluteToNdcY(context, clippedTop);
    const x1 = absoluteToNdcX(context, clippedRight);
    const y1 = absoluteToNdcY(context, clippedBottom);

    (*context.panels) ~= Vertex([x0, y0, z], color);
    (*context.panels) ~= Vertex([x1, y0, z], color);
    (*context.panels) ~= Vertex([x1, y1, z], color);

    (*context.panels) ~= Vertex([x0, y0, z], color);
    (*context.panels) ~= Vertex([x1, y1, z], color);
    (*context.panels) ~= Vertex([x0, y1, z], color);
}

/** Appends one already-generated textured text quad after clipping it in pixel space. */
private void appendClippedTexturedQuad(ref UiRenderContext context, ref Vertex[] vertices, Vertex[] quad)
{
    if (quad.length != 6)
        return;

    const left = ndcToAbsoluteX(context, quad[0].position[0]);
    const top = ndcToAbsoluteY(context, quad[0].position[1]);
    const right = ndcToAbsoluteX(context, quad[1].position[0]);
    const bottom = ndcToAbsoluteY(context, quad[2].position[1]);
    if (right <= left || bottom <= top)
        return;

    const clippedLeft = max(left, context.clipLeft);
    const clippedTop = max(top, context.clipTop);
    const clippedRight = min(right, context.clipRight);
    const clippedBottom = min(bottom, context.clipBottom);
    if (clippedRight <= clippedLeft || clippedBottom <= clippedTop)
        return;

    const u0 = quad[0].uv[0];
    const v0 = quad[0].uv[1];
    const u1 = quad[1].uv[0];
    const v1 = quad[2].uv[1];
    const uSpan = u1 - u0;
    const vSpan = v1 - v0;
    const width = right - left;
    const height = bottom - top;
    const clippedU0 = u0 + uSpan * ((clippedLeft - left) / width);
    const clippedU1 = u0 + uSpan * ((clippedRight - left) / width);
    const clippedV0 = v0 + vSpan * ((clippedTop - top) / height);
    const clippedV1 = v0 + vSpan * ((clippedBottom - top) / height);
    const z = quad[0].position[2];
    const color = quad[0].color;
    const x0 = absoluteToNdcX(context, clippedLeft);
    const y0 = absoluteToNdcY(context, clippedTop);
    const x1 = absoluteToNdcX(context, clippedRight);
    const y1 = absoluteToNdcY(context, clippedBottom);

    vertices ~= Vertex([x0, y0, z], color, [0.0f, 0.0f, 1.0f], [clippedU0, clippedV0]);
    vertices ~= Vertex([x1, y0, z], color, [0.0f, 0.0f, 1.0f], [clippedU1, clippedV0]);
    vertices ~= Vertex([x1, y1, z], color, [0.0f, 0.0f, 1.0f], [clippedU1, clippedV1]);

    vertices ~= Vertex([x0, y0, z], color, [0.0f, 0.0f, 1.0f], [clippedU0, clippedV0]);
    vertices ~= Vertex([x1, y1, z], color, [0.0f, 0.0f, 1.0f], [clippedU1, clippedV1]);
    vertices ~= Vertex([x0, y1, z], color, [0.0f, 0.0f, 1.0f], [clippedU0, clippedV1]);
}

/** Appends a colored triangle to the panel vertex buffer in normalized device space.
 *
 * Params:
 *   context = Active UI render context receiving panel vertices.
 *   x0Pixels = First point X coordinate in local pixels.
 *   y0Pixels = First point Y coordinate in local pixels.
 *   x1Pixels = Second point X coordinate in local pixels.
 *   y1Pixels = Second point Y coordinate in local pixels.
 *   x2Pixels = Third point X coordinate in local pixels.
 *   y2Pixels = Third point Y coordinate in local pixels.
 *   z = Depth value for the emitted triangle.
 *   color = Vertex color applied to the triangle.
 * Returns:
 *   Nothing.
 */
void appendTriangle(ref UiRenderContext context, float x0Pixels, float y0Pixels, float x1Pixels, float y1Pixels, float x2Pixels, float y2Pixels, float z, float[4] color)
{
    const x0 = toNdcX(context, x0Pixels);
    const y0 = toNdcY(context, y0Pixels);
    const x1 = toNdcX(context, x1Pixels);
    const y1 = toNdcY(context, y1Pixels);
    const x2 = toNdcX(context, x2Pixels);
    const y2 = toNdcY(context, y2Pixels);

    (*context.panels) ~= Vertex([x0, y0, z], color);
    (*context.panels) ~= Vertex([x1, y1, z], color);
    (*context.panels) ~= Vertex([x2, y2, z], color);
}

/** Converts a local X coordinate from pixels to normalized device space. */
float toNdcX(ref UiRenderContext context, float pixelX)
{
    return absoluteToNdcX(context, context.originX + pixelX);
}

/** Converts a local Y coordinate from pixels to normalized device space. */
float toNdcY(ref UiRenderContext context, float pixelY)
{
    return absoluteToNdcY(context, context.originY + pixelY);
}

/** Converts an absolute X coordinate from pixels to normalized device space. */
float absoluteToNdcX(ref UiRenderContext context, float pixelX)
{
    const extentWidth = safeExtent(context.extentWidth);
    return pixelX / extentWidth * 2.0f - 1.0f;
}

/** Converts an absolute Y coordinate from pixels to normalized device space. */
float absoluteToNdcY(ref UiRenderContext context, float pixelY)
{
    const extentHeight = safeExtent(context.extentHeight);
    return pixelY / extentHeight * 2.0f - 1.0f;
}

/** Converts an NDC X coordinate back to absolute pixels. */
float ndcToAbsoluteX(ref UiRenderContext context, float ndcX)
{
    return (ndcX + 1.0f) * 0.5f * safeExtent(context.extentWidth);
}

/** Converts an NDC Y coordinate back to absolute pixels. */
float ndcToAbsoluteY(ref UiRenderContext context, float ndcY)
{
    return (ndcY + 1.0f) * 0.5f * safeExtent(context.extentHeight);
}

/** Clamps invalid or zero extents to a safe positive fallback value. */
float safeExtent(float extent)
{
    return !isNaN(extent) && !isInfinity(extent) && extent > 0.0f ? extent : 1.0f;
}
