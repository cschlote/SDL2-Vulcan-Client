/** Implements retained UI widgets and frame rendering helpers.
 *
 * Provides the small widget tree, window and control primitives, and recursive
 * rendering helpers used by the retained overlay layer.
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.ui;

import vulkan.font : FontAtlas, appendText;
import vulkan.pipeline : Vertex;
import std.math : isInfinity, isNaN;

/** Selects the font size used by a widget. */
enum UiTextStyle
{
    /** Small body text. */
    small,
    /** Medium labels and titles. */
    medium,
    /** Large comparison text. */
    large,
}

/** Collects the geometry targets and font atlases for a UI frame.
 *
 * Widgets render into the shared overlay buffers through this context. The
 * renderer feeds it with the three atlas sizes and the per-frame vertex lists.
 */
struct UiRenderContext
{
    /** Target viewport width in pixels. */
    float extentWidth;
    /** Target viewport height in pixels. */
    float extentHeight;
    /** Current X offset relative to the parent widget. */
    float originX;
    /** Current Y offset relative to the parent widget. */
    float originY;
    /** Base Z depth used to keep widget layers stable. */
    float depthBase;
    /** Font atlas for small text. */
    const(FontAtlas)* smallFont;
    /** Font atlas for medium text. */
    const(FontAtlas)* mediumFont;
    /** Font atlas for large text. */
    const(FontAtlas)* largeFont;
    /** Destination vertex list for window and panel quads. */
    Vertex[]* panels;
    /** Destination vertex list for small text quads. */
    Vertex[]* smallText;
    /** Destination vertex list for medium text quads. */
    Vertex[]* mediumText;
    /** Destination vertex list for large text quads. */
    Vertex[]* largeText;

    /** Creates a child context relative to the current origin. */
    UiRenderContext offset(float deltaX, float deltaY)
    {
        auto next = this;
        next.originX += deltaX;
        next.originY += deltaY;
        return next;
    }

    /** Returns the font atlas for the requested text style. */
    const(FontAtlas)* atlasFor(UiTextStyle style) const
    {
        final switch (style)
        {
            case UiTextStyle.small: return smallFont;
            case UiTextStyle.medium: return mediumFont;
            case UiTextStyle.large: return largeFont;
        }
    }
}

/** Base class for all retained UI widgets.
 *
 * The retained tree mirrors the overlay structure used by the demo: each
 * widget can have children, can offset them relative to its content region,
 * and can render itself into the shared frame context.
 */
abstract class UiWidget
{
    /** Widget origin relative to its parent. */
    float x;
    /** Widget origin relative to its parent. */
    float y;
    /** Widget width in pixels. */
    float width;
    /** Widget height in pixels. */
    float height;
    /** X offset applied to child widgets. */
    float childOffsetX;
    /** Y offset applied to child widgets. */
    float childOffsetY;
    /** Whether the widget participates in rendering. */
    bool visible = true;
    /** Child widgets rendered after the parent. */
    UiWidget[] children;

    this(float x = 0, float y = 0, float width = 0, float height = 0)
    {
        this.x = x;
        this.y = y;
        this.width = width;
        this.height = height;
        childOffsetX = 0.0f;
        childOffsetY = 0.0f;
    }

    /** Adds a child widget below this widget in the visual tree. */
    void add(UiWidget child)
    {
        children ~= child;
    }

    /** Renders the widget and its children in back-to-front order. */
    final void render(ref UiRenderContext context)
    {
        if (!visible)
            return;

        auto localContext = context.offset(x, y);
        renderSelf(localContext);

        auto childContext = localContext.offset(childOffsetX, childOffsetY);
        foreach (index, child; children)
        {
            childContext.depthBase = localContext.depthBase - cast(float)index * 0.001f;
            child.render(childContext);
        }
    }

protected:
    /** Renders the widget's own visual representation. */
    abstract void renderSelf(ref UiRenderContext context);
}

/** Root container that only renders its children.
 *
 * This provides a neutral root for assembling widget trees without adding a
 * visible background of its own.
 */
final class UiContainer : UiWidget
{
    this()
    {
        super(0, 0, 0, 0);
        childOffsetX = 0.0f;
        childOffsetY = 0.0f;
    }

protected:
    override void renderSelf(ref UiRenderContext context)
    {
    }
}

/** Simple retained window with a title bar and a content region.
 *
 * Windows are the main organizing primitive for the HUD overlay; they draw a
 * body quad, a header strip, and then render their children inside the content
 * region.
 */
final class UiWindow : UiWidget
{
    /** Window title displayed in the header bar. */
    string title;
    /** Body fill color. */
    float[4] bodyColor;
    /** Header strip color. */
    float[4] headerColor;
    /** Title text color. */
    float[4] titleColor;
    /** Header strip height in pixels. */
    float headerHeight = 7.0f;

    this(string title, float x, float y, float width, float height, float[4] bodyColor, float[4] headerColor, float[4] titleColor)
    {
        super(x, y, width, height);
        this.title = title;
        this.bodyColor = bodyColor;
        this.headerColor = headerColor;
        this.titleColor = titleColor;
        childOffsetX = 18.0f;
        childOffsetY = 36.0f;
    }

protected:
    override void renderSelf(ref UiRenderContext context)
    {
        appendWindowFrame(context, 0.0f, 0.0f, width, height, bodyColor, headerColor, context.depthBase);
        appendTextLine(context, UiTextStyle.medium, title, 12.0f, 6.0f, titleColor, context.depthBase - 0.001f);
    }
}

/** Simple text widget.
 *
 * Labels are the basic building blocks for the retained UI examples and they
 * reuse the shared atlas selection logic in the render context.
 */
final class UiLabel : UiWidget
{
    /** Text content to render. */
    string text;
    /** Selected text style. */
    UiTextStyle style;
    /** RGBA text color. */
    float[4] color;

    this(string text, float x, float y, UiTextStyle style, float[4] color)
    {
        super(x, y, 0, 0);
        this.text = text;
        this.style = style;
        this.color = color;
    }

protected:
    override void renderSelf(ref UiRenderContext context)
    {
        appendTextLine(context, style, text, 0.0f, 0.0f, color, context.depthBase - 0.001f);
    }
}

/** Simple gadget-style button used for future interactive UI work.
 *
 * Buttons are currently rendered only; the retained input path can later reuse
 * this type for hit testing and activation.
 */
final class UiButton : UiWidget
{
    /** Button caption. */
    string caption;
    /** Filled body color. */
    float[4] bodyColor;
    /** Border color. */
    float[4] borderColor;
    /** Button text color. */
    float[4] textColor;
    /** Text style used for the caption. */
    UiTextStyle style;

    this(string caption, float x, float y, float width, float height, float[4] bodyColor, float[4] borderColor, float[4] textColor, UiTextStyle style = UiTextStyle.small)
    {
        super(x, y, width, height);
        this.caption = caption;
        this.bodyColor = bodyColor;
        this.borderColor = borderColor;
        this.textColor = textColor;
        this.style = style;
    }

protected:
    override void renderSelf(ref UiRenderContext context)
    {
        appendButtonFrame(context, 0.0f, 0.0f, width, height, bodyColor, borderColor, context.depthBase);
        appendTextLine(context, style, caption, 10.0f, 5.0f, textColor, context.depthBase - 0.001f);
    }
}

/** Appends the body and header quads for a retained window frame. */
private void appendWindowFrame(ref UiRenderContext context, float left, float top, float right, float bottom, float[4] bodyColor, float[4] headerColor, float z)
{
    if (right <= left || bottom <= top)
        return;

    appendQuad(context, left, top, right, bottom, z, bodyColor);
    appendQuad(context, left, top, right, top + 7.0f, z - 0.001f, headerColor);
    appendQuad(context, left, top, right, top + 1.0f, z - 0.002f, [0.98f, 0.98f, 1.0f, 0.46f]);
    appendQuad(context, left, bottom - 1.0f, right, bottom, z - 0.002f, [0.98f, 0.98f, 1.0f, 0.26f]);
    appendQuad(context, left, top, left + 1.0f, bottom, z - 0.002f, [0.98f, 0.98f, 1.0f, 0.26f]);
    appendQuad(context, right - 1.0f, top, right, bottom, z - 0.002f, [0.98f, 0.98f, 1.0f, 0.26f]);
}

/** Appends the button body and border quads for the retained UI style. */
private void appendButtonFrame(ref UiRenderContext context, float left, float top, float right, float bottom, float[4] bodyColor, float[4] borderColor, float z)
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
private void appendTextLine(ref UiRenderContext context, UiTextStyle style, string text, float x, float y, float[4] color, float z)
{
    const atlas = context.atlasFor(style);
    auto vertices = textVerticesFor(context, style);

    if (atlas is null || vertices is null)
        return;

    appendText(*vertices, *atlas, text, context.originX + x, context.originY + y, z, color, context.extentWidth, context.extentHeight);
}

/** Returns the active vertex buffer for the requested text style. */
private Vertex[]* textVerticesFor(ref UiRenderContext context, UiTextStyle style)
{
    final switch (style)
    {
        case UiTextStyle.small: return context.smallText;
        case UiTextStyle.medium: return context.mediumText;
        case UiTextStyle.large: return context.largeText;
    }
}

/** Appends a colored quad to the panel vertex buffer in normalized device space. */
private void appendQuad(ref UiRenderContext context, float left, float top, float right, float bottom, float z, float[4] color)
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
private float toNdcX(ref UiRenderContext context, float pixelX)
{
    const extentWidth = safeExtent(context.extentWidth);
    return (context.originX + pixelX) / extentWidth * 2.0f - 1.0f;
}

/** Converts a local Y coordinate from pixels to normalized device space. */
private float toNdcY(ref UiRenderContext context, float pixelY)
{
    const extentHeight = safeExtent(context.extentHeight);
    return (context.originY + pixelY) / extentHeight * 2.0f - 1.0f;
}

/** Clamps invalid or zero extents to a safe positive fallback value. */
private float safeExtent(float extent)
{
    return !isNaN(extent) && !isInfinity(extent) && extent > 0.0f ? extent : 1.0f;
}
