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

import std.math : isInfinity, isNaN;

import vulkan.font.font_legacy : appendText;
import vulkan.engine.pipeline : Vertex;
import vulkan.ui.ui_context : UiRenderContext, UiTextStyle;

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

/** Appends the body and header quads for a retained window frame.
 *
 * The header fill can reserve horizontal insets so the decorative surface
 * stays clear of close buttons, resize grips, and header extras.
 */
void appendWindowFrame(ref UiRenderContext context, float left, float top, float right, float bottom, float headerHeight, float[4] bodyColor, float[4] headerColor, float z, float headerLeftInset = 0.0f, float headerRightInset = 0.0f)
{
    if (right <= left || bottom <= top)
        return;

    appendQuad(context, left, top, right, bottom, z, bodyColor);

    // const headerLeft = left + headerLeftInset;
    // const headerRight = right - headerRightInset;
    // if (headerRight > headerLeft)
    //     appendQuad(context, headerLeft, top, headerRight, top + headerHeight, z - 0.001f, headerColor);

    appendQuad(context, left, top + headerHeight - 2.0f, right, top + headerHeight - 1.0f, z - 0.002f, [0.10f, 0.10f, 0.12f, 0.70f]);
    appendQuad(context, left, top + headerHeight - 1.0f, right, top + headerHeight, z - 0.002f, [0.98f, 0.98f, 1.0f, 0.48f]);
}

/** Appends the outer border quads for a retained window frame. */
void appendWindowBorder(ref UiRenderContext context, float left, float top, float right, float bottom, float z)
{
    appendQuad(context, left, top, right, top + 2.0f, z - 0.002f, [0.98f, 0.98f, 1.0f, 0.34f]);
    appendQuad(context, left, bottom - 1.0f, right, bottom, z - 0.002f, [0.98f, 0.98f, 1.0f, 0.26f]);
    appendQuad(context, left, top, left + 1.0f, bottom, z - 0.002f, [0.98f, 0.98f, 1.0f, 0.26f]);
    appendQuad(context, right - 1.0f, top, right, bottom, z - 0.002f, [0.98f, 0.98f, 1.0f, 0.26f]);
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

    appendText(*vertices, *atlas, text, context.originX + x, context.originY + y, z, color, context.extentWidth, context.extentHeight);
}

/** Returns the active vertex buffer for the requested text style. */
Vertex[]* textVerticesFor(ref UiRenderContext context, UiTextStyle style)
{
    return context.textVerticesFor(style);
}

/** Appends a colored quad to the panel vertex buffer in normalized device space. */
void appendQuad(ref UiRenderContext context, float left, float top, float right, float bottom, float z, float[4] color)
{
    const x0 = toNdcX(context, left);
    const y0 = toNdcY(context, top);
    const x1 = toNdcX(context, right);
    const y1 = toNdcY(context, bottom);

    (*context.panels) ~= Vertex([x0, y0, z], color);
    (*context.panels) ~= Vertex([x1, y0, z], color);
    (*context.panels) ~= Vertex([x1, y1, z], color);

    (*context.panels) ~= Vertex([x0, y0, z], color);
    (*context.panels) ~= Vertex([x1, y1, z], color);
    (*context.panels) ~= Vertex([x0, y1, z], color);
}

/** Converts a local X coordinate from pixels to normalized device space. */
float toNdcX(ref UiRenderContext context, float pixelX)
{
    const extentWidth = safeExtent(context.extentWidth);
    return (context.originX + pixelX) / extentWidth * 2.0f - 1.0f;
}

/** Converts a local Y coordinate from pixels to normalized device space. */
float toNdcY(ref UiRenderContext context, float pixelY)
{
    const extentHeight = safeExtent(context.extentHeight);
    return (context.originY + pixelY) / extentHeight * 2.0f - 1.0f;
}

/** Clamps invalid or zero extents to a safe positive fallback value. */
float safeExtent(float extent)
{
    return !isNaN(extent) && !isInfinity(extent) && extent > 0.0f ? extent : 1.0f;
}
