/** Retained layout widgets for box and grid based UI composition.
 *
 * The layout widgets keep the geometry rules small and explicit so retained
 * windows can use vertical stacks, horizontal rows, and simple grids without
 * manually placing every child widget.
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.ui.ui_layout;

import std.algorithm : max;
import vulkan.engine.pipeline : Vertex;
import vulkan.ui.ui_context : UiRenderContext;
import vulkan.ui.ui_event : UiPointerEvent, UiPointerEventKind;
import vulkan.ui.ui_layout_context : UiLayoutContext, UiLayoutSize;
import vulkan.ui.ui_widget_helpers : appendQuad, appendSurfaceFrame;
import vulkan.ui.ui_widget : UiWidget;

private immutable float[4] contentBoxDebugBoundsColor = [0.15f, 0.95f, 1.00f, 0.65f];
private immutable float[4] verticalLayoutDebugBoundsColor = [0.20f, 1.00f, 0.35f, 0.65f];
private immutable float[4] horizontalLayoutDebugBoundsColor = [0.20f, 0.50f, 1.00f, 0.65f];
private immutable float[4] gridLayoutDebugBoundsColor = [0.90f, 0.30f, 1.00f, 0.65f];
private immutable float[4] spacerDebugBoundsColor = [1.00f, 1.00f, 0.20f, 0.45f];
private immutable float[4] scrollAreaDebugBoundsColor = [1.00f, 0.72f, 0.18f, 0.65f];
private immutable float[4] scrollTrackColor = [0.02f, 0.03f, 0.04f, 0.34f];
private immutable float[4] scrollThumbColor = [0.78f, 0.84f, 0.90f, 0.58f];
private immutable float[4] scrollFadeColor = [0.02f, 0.03f, 0.04f, 0.42f];
private immutable float[4] separatorColor = [0.78f, 0.84f, 0.90f, 0.30f];
private enum float scrollIndicatorThickness = 5.0f;
private enum float scrollFadeSize = 12.0f;

/** Axis direction for non-interactive layout separators. */
enum UiSeparatorOrientation
{
    horizontal,
    vertical,
}

/** Invisible widget that only contributes space to a layout. */
final class UiSpacer : UiWidget
{
    private float naturalWidth;
    private float naturalHeight;

    this(float width = 0.0f, float height = 0.0f)
    {
        super(0.0f, 0.0f, width, height);
        naturalWidth = width;
        naturalHeight = height;
    }

protected:
    override UiLayoutSize measureSelf(ref UiLayoutContext context)
    {
        const measuredWidth = preferredWidth > 0.0f ? preferredWidth : naturalWidth;
        const measuredHeight = preferredHeight > 0.0f ? preferredHeight : naturalHeight;
        return UiLayoutSize(measuredWidth, measuredHeight);
    }

    override void renderSelf(ref UiRenderContext context)
    {
    }

    override bool dispatchPointerEvent(ref UiPointerEvent event)
    {
        return false;
    }

    override float[4] debugBoundsColor() const
    {
        return cast(float[4])spacerDebugBoundsColor;
    }
}

/** Non-interactive visual divider for grouped retained UI content. */
final class UiSeparator : UiWidget
{
    UiSeparatorOrientation orientation;
    float thickness;
    float[4] color;

    this(UiSeparatorOrientation orientation = UiSeparatorOrientation.horizontal, float length = 0.0f, float thickness = 1.0f)
    {
        const width = orientation == UiSeparatorOrientation.horizontal ? length : thickness;
        const height = orientation == UiSeparatorOrientation.horizontal ? thickness : length;
        super(0.0f, 0.0f, width, height);
        this.orientation = orientation;
        this.thickness = thickness > 0.0f ? thickness : 1.0f;
        color = cast(float[4])separatorColor;
        if (orientation == UiSeparatorOrientation.horizontal)
            setLayoutHint(0.0f, this.thickness, length, this.thickness, float.max, this.thickness, 1.0f, 0.0f);
        else
            setLayoutHint(this.thickness, 0.0f, this.thickness, length, this.thickness, float.max, 0.0f, 1.0f);
    }

protected:
    override UiLayoutSize measureSelf(ref UiLayoutContext context)
    {
        if (orientation == UiSeparatorOrientation.horizontal)
            return UiLayoutSize(preferredWidth > 0.0f ? preferredWidth : width, thickness);
        return UiLayoutSize(thickness, preferredHeight > 0.0f ? preferredHeight : height);
    }

    override void renderSelf(ref UiRenderContext context)
    {
        if (orientation == UiSeparatorOrientation.horizontal)
        {
            const top = height > thickness ? (height - thickness) * 0.5f : 0.0f;
            appendQuad(context, 0.0f, top, width, top + thickness, context.depthBase, color);
        }
        else
        {
            const left = width > thickness ? (width - thickness) * 0.5f : 0.0f;
            appendQuad(context, left, 0.0f, left + thickness, height, context.depthBase, color);
        }
    }

    override bool dispatchPointerEvent(ref UiPointerEvent event)
    {
        return false;
    }

    override float[4] debugBoundsColor() const
    {
        return cast(float[4])spacerDebugBoundsColor;
    }
}

@("UiVBox can shrink children after a previous larger layout")
unittest
{
    auto column = new UiVBox(0.0f, 0.0f, 100.0f, 120.0f, 0.0f);
    auto child = new UiSpacer(10.0f, 20.0f);
    child.setLayoutHint(10.0f, 20.0f, 10.0f, 20.0f, float.max, float.max, 1.0f, 1.0f);
    column.add(child);

    UiLayoutContext context;
    column.layout(context);
    assert(child.height == 120.0f);

    column.height = 60.0f;
    column.layout(context);
    assert(child.height == 60.0f);
}

@("UiSpacer keeps its intrinsic size after grow layout")
unittest
{
    auto column = new UiVBox(0.0f, 0.0f, 100.0f, 120.0f, 0.0f);
    auto child = new UiSpacer();
    child.setLayoutHint(0.0f, 0.0f, 0.0f, 0.0f, float.max, float.max, 0.0f, 1.0f);
    column.add(child);

    UiLayoutContext context;
    column.layout(context);
    assert(child.height == 120.0f);

    const measured = child.measure(context);
    assert(measured.height == 0.0f);
}

@("UiSeparator exposes horizontal and vertical layout hints")
unittest
{
    auto horizontal = new UiSeparator(UiSeparatorOrientation.horizontal, 80.0f, 2.0f);
    assert(horizontal.minimumHeight == 2.0f);
    assert(horizontal.maximumHeight == 2.0f);
    assert(horizontal.flexGrowX == 1.0f);
    assert(horizontal.flexGrowY == 0.0f);

    auto vertical = new UiSeparator(UiSeparatorOrientation.vertical, 40.0f, 3.0f);
    assert(vertical.minimumWidth == 3.0f);
    assert(vertical.maximumWidth == 3.0f);
    assert(vertical.flexGrowX == 0.0f);
    assert(vertical.flexGrowY == 1.0f);

    UiPointerEvent event;
    event.kind = UiPointerEventKind.buttonDown;
    event.button = 1;
    event.x = 1.0f;
    event.y = 1.0f;
    assert(!horizontal.dispatchPointerEvent(event));
}

private float clampFloat(float value, float minimum, float maximum)
{
    return value < minimum ? minimum : (value > maximum ? maximum : value);
}

private struct AxisHint
{
    float minimum;
    float preferred;
    float maximum;
    float grow;
}

private AxisHint horizontalHint(UiWidget child)
{
    AxisHint hint;
    hint.minimum = child.minimumWidth > 0.0f ? child.minimumWidth : child.preferredWidth > 0.0f ? child.preferredWidth : child.flexGrowX > 0.0f ? 0.0f : child.width;
    hint.preferred = child.preferredWidth > 0.0f ? child.preferredWidth : child.flexGrowX > 0.0f ? 0.0f : child.width;
    hint.maximum = child.maximumWidth > 0.0f ? child.maximumWidth : float.max;
    hint.grow = child.flexGrowX;
    return hint;
}

private AxisHint verticalHint(UiWidget child)
{
    AxisHint hint;
    hint.minimum = child.minimumHeight > 0.0f ? child.minimumHeight : child.preferredHeight > 0.0f ? child.preferredHeight : child.flexGrowY > 0.0f ? 0.0f : child.height;
    hint.preferred = child.preferredHeight > 0.0f ? child.preferredHeight : child.flexGrowY > 0.0f ? 0.0f : child.height;
    hint.maximum = child.maximumHeight > 0.0f ? child.maximumHeight : float.max;
    hint.grow = child.flexGrowY;
    return hint;
}

private float[] resolveSizes(UiWidget[] children, float availableSpace, bool horizontal)
{
    float[] sizes;
    sizes.length = children.length;

    float preferredTotal = 0.0f;
    float minimumTotal = 0.0f;
    float growTotal = 0.0f;

    foreach (index, child; children)
    {
        const hint = horizontal ? horizontalHint(child) : verticalHint(child);
        const minimum = hint.minimum > 0.0f ? hint.minimum : 0.0f;
        const preferred = hint.preferred > 0.0f ? hint.preferred : minimum;
        sizes[index] = clampFloat(preferred, minimum, hint.maximum);
        preferredTotal += sizes[index];
        minimumTotal += minimum;
        if (hint.grow > 0.0f)
            growTotal += hint.grow;
    }

    if (availableSpace > preferredTotal && growTotal > 0.0f)
    {
        const extraSpace = availableSpace - preferredTotal;
        foreach (index, child; children)
        {
            const hint = horizontal ? horizontalHint(child) : verticalHint(child);
            if (hint.grow <= 0.0f)
                continue;

            const grown = sizes[index] + extraSpace * (hint.grow / growTotal);
            sizes[index] = clampFloat(grown, hint.minimum > 0.0f ? hint.minimum : 0.0f, hint.maximum);
        }
    }
    else if (availableSpace < preferredTotal && preferredTotal > minimumTotal)
    {
        const shortage = preferredTotal - availableSpace;
        const shrinkableTotal = preferredTotal - minimumTotal;

        foreach (index, child; children)
        {
            const hint = horizontal ? horizontalHint(child) : verticalHint(child);
            const minimum = hint.minimum > 0.0f ? hint.minimum : 0.0f;
            const shrinkable = sizes[index] - minimum;
            if (shrinkable <= 0.0f)
                continue;

            const shrunken = sizes[index] - shortage * (shrinkable / shrinkableTotal);
            sizes[index] = clampFloat(shrunken, minimum, hint.maximum);
        }
    }

    return sizes;
}

/** Shared base for retained layout containers. */
abstract class UiLayoutContainer : UiWidget
{
    float paddingLeft;
    float paddingTop;
    float paddingRight;
    float paddingBottom;

    this(float x = 0.0f, float y = 0.0f, float width = 0.0f, float height = 0.0f, float paddingLeft = 0.0f, float paddingTop = 0.0f, float paddingRight = 0.0f, float paddingBottom = 0.0f)
    {
        super(x, y, width, height);
        flexGrowX = 1.0f;
        flexGrowY = 0.0f;
        this.paddingLeft = paddingLeft;
        this.paddingTop = paddingTop;
        this.paddingRight = paddingRight;
        this.paddingBottom = paddingBottom;
    }

    override bool dispatchPointerEvent(ref UiPointerEvent event)
    {
        layoutChildren();
        return super.dispatchPointerEvent(event);
    }

protected:
    override void renderSelf(ref UiRenderContext context)
    {
        layoutChildren();
    }

    abstract void layoutChildren();

    float innerWidth() const
    {
        return width > paddingLeft + paddingRight ? width - paddingLeft - paddingRight : 0.0f;
    }

    float innerHeight() const
    {
        return height > paddingTop + paddingBottom ? height - paddingTop - paddingBottom : 0.0f;
    }
}

/** Shared implementation for content and framed layout boxes. */
abstract class UiBoxBase : UiLayoutContainer
{
    float[4] backgroundColor;
    float[4] borderColor;
    bool drawBorder;
    bool drawBackground;

    this(float x = 0.0f, float y = 0.0f, float width = 0.0f, float height = 0.0f, float[4] backgroundColor = [0.0f, 0.0f, 0.0f, 0.0f], float[4] borderColor = [0.0f, 0.0f, 0.0f, 0.0f], float paddingLeft = 0.0f, float paddingTop = 0.0f, float paddingRight = 0.0f, float paddingBottom = 0.0f, bool drawBackground = false, bool drawBorder = false)
    {
        super(x, y, width, height, paddingLeft, paddingTop, paddingRight, paddingBottom);
        this.backgroundColor = backgroundColor;
        this.borderColor = borderColor;
        this.drawBackground = drawBackground;
        this.drawBorder = drawBorder;
    }

protected:
    override UiLayoutSize measureSelf(ref UiLayoutContext context)
    {
        float widest = 0.0f;
        float tallest = 0.0f;

        foreach (child; children)
        {
            const childSize = child.measure(context);
            if (childSize.width > widest)
                widest = childSize.width;
            if (childSize.height > tallest)
                tallest = childSize.height;
        }

        const measuredWidth = preferredWidth > 0.0f ? preferredWidth : widest + paddingLeft + paddingRight;
        const measuredHeight = preferredHeight > 0.0f ? preferredHeight : tallest + paddingTop + paddingBottom;
        return UiLayoutSize(measuredWidth, measuredHeight);
    }

    override void renderSelf(ref UiRenderContext context)
    {
        appendSurfaceFrame(context, 0.0f, 0.0f, width, height, backgroundColor, borderColor, context.depthBase, drawBackground, drawBorder);
        layoutChildren();
    }

    override void layoutChildren()
    {
    }

    override void layoutSelf(ref UiLayoutContext context)
    {
        foreach (child; children)
        {
            child.x = paddingLeft;
            child.y = paddingTop;
            child.width = innerWidth();
            child.height = innerHeight();
            child.layout(context);
        }
    }

    override float[4] debugBoundsColor() const
    {
        return cast(float[4])contentBoxDebugBoundsColor;
    }
}

/** Padded content root that assigns one useful inner rectangle to its children. */
final class UiContentBox : UiBoxBase
{
    this(float x = 0.0f, float y = 0.0f, float width = 0.0f, float height = 0.0f, float paddingLeft = 0.0f, float paddingTop = 0.0f, float paddingRight = 0.0f, float paddingBottom = 0.0f)
    {
        super(x, y, width, height, [0.0f, 0.0f, 0.0f, 0.0f], [0.0f, 0.0f, 0.0f, 0.0f], paddingLeft, paddingTop, paddingRight, paddingBottom, false, false);
    }
}

/** Visible framed box for grouping content with an optional background. */
final class UiFrameBox : UiBoxBase
{
    this(float x = 0.0f, float y = 0.0f, float width = 0.0f, float height = 0.0f, float[4] backgroundColor = [0.0f, 0.0f, 0.0f, 0.0f], float[4] borderColor = [0.0f, 0.0f, 0.0f, 0.0f], float paddingLeft = 0.0f, float paddingTop = 0.0f, float paddingRight = 0.0f, float paddingBottom = 0.0f)
    {
        super(x, y, width, height, backgroundColor, borderColor, paddingLeft, paddingTop, paddingRight, paddingBottom, true, true);
    }
}

@("UiContentBox lays out children inside padding")
unittest
{
    auto box = new UiContentBox(0.0f, 0.0f, 100.0f, 80.0f, 4.0f, 5.0f, 6.0f, 7.0f);
    auto child = new UiSpacer();
    box.add(child);

    UiLayoutContext context;
    box.layout(context);

    assert(child.x == 4.0f);
    assert(child.y == 5.0f);
    assert(child.width == 90.0f);
    assert(child.height == 68.0f);
    assert(!box.drawBackground);
    assert(!box.drawBorder);
}

@("UiFrameBox renders as visible framed content container")
unittest
{
    auto box = new UiFrameBox(0.0f, 0.0f, 100.0f, 80.0f, [0.1f, 0.2f, 0.3f, 1.0f], [0.4f, 0.5f, 0.6f, 1.0f]);

    assert(box.drawBackground);
    assert(box.drawBorder);
}

/** Scrollable viewport for content that can exceed the visible area. */
final class UiScrollArea : UiLayoutContainer
{
    float scrollX;
    float scrollY;
    float contentWidth;
    float contentHeight;
    float wheelStep = 32.0f;

    this(float x = 0.0f, float y = 0.0f, float width = 0.0f, float height = 0.0f, float paddingLeft = 0.0f, float paddingTop = 0.0f, float paddingRight = 0.0f, float paddingBottom = 0.0f)
    {
        super(x, y, width, height, paddingLeft, paddingTop, paddingRight, paddingBottom);
        scrollX = 0.0f;
        scrollY = 0.0f;
        contentWidth = 0.0f;
        contentHeight = 0.0f;
        flexGrowX = 1.0f;
        flexGrowY = 1.0f;
    }

    void scrollTo(float x, float y)
    {
        scrollX = clampFloat(x, 0.0f, maxScrollX());
        scrollY = clampFloat(y, 0.0f, maxScrollY());
        childOffsetX = -scrollX;
        childOffsetY = -scrollY;
    }

    float maxScrollX() const
    {
        const viewportWidth = innerWidth();
        return contentWidth > viewportWidth ? contentWidth - viewportWidth : 0.0f;
    }

    float maxScrollY() const
    {
        const viewportHeight = innerHeight();
        return contentHeight > viewportHeight ? contentHeight - viewportHeight : 0.0f;
    }

    bool canScroll() const
    {
        return maxScrollX() > 0.0f || maxScrollY() > 0.0f;
    }

    float verticalThumbTop() const
    {
        const maxY = maxScrollY();
        if (maxY <= 0.0f)
            return paddingTop;

        const viewportHeight = innerHeight();
        const trackTop = paddingTop;
        const trackHeight = viewportHeight;
        const thumbHeight = verticalThumbHeight();
        const travel = trackHeight > thumbHeight ? trackHeight - thumbHeight : 0.0f;
        return trackTop + travel * (scrollY / maxY);
    }

    float verticalThumbHeight() const
    {
        const viewportHeight = innerHeight();
        if (contentHeight <= 0.0f || viewportHeight <= 0.0f)
            return 0.0f;

        const ratio = viewportHeight / contentHeight;
        const minimum = scrollIndicatorThickness * 3.0f;
        return clampFloat(viewportHeight * ratio, minimum, viewportHeight);
    }

    float horizontalThumbLeft() const
    {
        const maxX = maxScrollX();
        if (maxX <= 0.0f)
            return paddingLeft;

        const viewportWidth = innerWidth();
        const trackLeft = paddingLeft;
        const trackWidth = viewportWidth;
        const thumbWidth = horizontalThumbWidth();
        const travel = trackWidth > thumbWidth ? trackWidth - thumbWidth : 0.0f;
        return trackLeft + travel * (scrollX / maxX);
    }

    float horizontalThumbWidth() const
    {
        const viewportWidth = innerWidth();
        if (contentWidth <= 0.0f || viewportWidth <= 0.0f)
            return 0.0f;

        const ratio = viewportWidth / contentWidth;
        const minimum = scrollIndicatorThickness * 3.0f;
        return clampFloat(viewportWidth * ratio, minimum, viewportWidth);
    }

protected:
    override UiLayoutSize measureSelf(ref UiLayoutContext context)
    {
        if (children.length == 0)
            return UiLayoutSize(preferredWidth > 0.0f ? preferredWidth : width, preferredHeight > 0.0f ? preferredHeight : height);

        const childSize = children[0].measure(context);
        const measuredWidth = preferredWidth > 0.0f ? preferredWidth : childSize.width + paddingLeft + paddingRight;
        const measuredHeight = preferredHeight > 0.0f ? preferredHeight : childSize.height + paddingTop + paddingBottom;
        return UiLayoutSize(measuredWidth, measuredHeight);
    }

    override void layoutChildren()
    {
        foreach (child; children)
        {
            child.x = paddingLeft;
            child.y = paddingTop;
            child.width = contentWidth > 0.0f ? contentWidth : innerWidth();
            child.height = contentHeight > 0.0f ? contentHeight : innerHeight();
        }
    }

    override void layoutSelf(ref UiLayoutContext context)
    {
        float measuredWidth = 0.0f;
        float measuredHeight = 0.0f;

        foreach (child; children)
        {
            const childSize = child.measure(context);
            if (childSize.width > measuredWidth)
                measuredWidth = childSize.width;
            if (childSize.height > measuredHeight)
                measuredHeight = childSize.height;
        }

        contentWidth = measuredWidth > innerWidth() ? measuredWidth : innerWidth();
        contentHeight = measuredHeight > innerHeight() ? measuredHeight : innerHeight();
        scrollTo(scrollX, scrollY);

        foreach (child; children)
        {
            child.x = paddingLeft;
            child.y = paddingTop;
            child.width = contentWidth;
            child.height = contentHeight;
            child.layout(context);
        }
    }

    override void renderSelf(ref UiRenderContext context)
    {
        layoutChildren();

        const maxX = maxScrollX();
        const maxY = maxScrollY();
        const viewportLeft = paddingLeft;
        const viewportTop = paddingTop;
        const viewportRight = paddingLeft + innerWidth();
        const viewportBottom = paddingTop + innerHeight();
        const zBase = context.depthBase - 0.020f;

        if (maxY > 0.0f)
        {
            const trackLeft = viewportRight - scrollIndicatorThickness;
            appendQuad(context, trackLeft, viewportTop, viewportRight, viewportBottom, zBase, scrollTrackColor);

            const thumbTop = verticalThumbTop();
            const thumbBottom = thumbTop + verticalThumbHeight();
            appendQuad(context, trackLeft, thumbTop, viewportRight, thumbBottom, zBase - 0.001f, scrollThumbColor);

            if (scrollY > 0.0f)
                appendQuad(context, viewportLeft, viewportTop, viewportRight, viewportTop + scrollFadeSize, zBase - 0.002f, scrollFadeColor);
            if (scrollY < maxY)
                appendQuad(context, viewportLeft, viewportBottom - scrollFadeSize, viewportRight, viewportBottom, zBase - 0.002f, scrollFadeColor);
        }

        if (maxX > 0.0f)
        {
            const trackTop = viewportBottom - scrollIndicatorThickness;
            appendQuad(context, viewportLeft, trackTop, viewportRight, viewportBottom, zBase, scrollTrackColor);

            const thumbLeft = horizontalThumbLeft();
            const thumbRight = thumbLeft + horizontalThumbWidth();
            appendQuad(context, thumbLeft, trackTop, thumbRight, viewportBottom, zBase - 0.001f, scrollThumbColor);

            if (scrollX > 0.0f)
                appendQuad(context, viewportLeft, viewportTop, viewportLeft + scrollFadeSize, viewportBottom, zBase - 0.002f, scrollFadeColor);
            if (scrollX < maxX)
                appendQuad(context, viewportRight - scrollFadeSize, viewportTop, viewportRight, viewportBottom, zBase - 0.002f, scrollFadeColor);
        }
    }

    override bool handlePointerEvent(ref UiPointerEvent event)
    {
        if (event.kind != UiPointerEventKind.wheel)
            return false;

        const oldScrollX = scrollX;
        const oldScrollY = scrollY;
        const wheelX = event.wheelX == event.wheelX ? event.wheelX : 0.0f;
        const wheelY = event.wheelY == event.wheelY ? event.wheelY : 0.0f;
        scrollTo(scrollX - wheelX * wheelStep, scrollY - wheelY * wheelStep);
        return scrollX != oldScrollX || scrollY != oldScrollY;
    }

    override UiRenderContext childRenderContext(UiRenderContext context)
    {
        return context.clipped(paddingLeft + scrollX, paddingTop + scrollY, paddingLeft + scrollX + innerWidth(), paddingTop + scrollY + innerHeight());
    }

    override float[4] debugBoundsColor() const
    {
        return cast(float[4])scrollAreaDebugBoundsColor;
    }
}

@("UiScrollArea clamps wheel scrolling to content bounds")
unittest
{
    auto area = new UiScrollArea(0.0f, 0.0f, 100.0f, 80.0f);
    auto content = new UiSpacer(100.0f, 200.0f);
    area.add(content);

    UiLayoutContext context;
    area.layout(context);
    assert(area.maxScrollY() == 120.0f);

    UiPointerEvent event;
    event.kind = UiPointerEventKind.wheel;
    event.x = 20.0f;
    event.y = 20.0f;
    event.wheelY = -10.0f;
    assert(area.dispatchPointerEvent(event));
    assert(area.scrollY == 120.0f);

    event.wheelY = 10.0f;
    assert(area.dispatchPointerEvent(event));
    assert(area.scrollY == 0.0f);
}

@("UiScrollArea derives visible indicator geometry from scroll offsets")
unittest
{
    auto area = new UiScrollArea(0.0f, 0.0f, 100.0f, 80.0f);
    auto content = new UiSpacer(200.0f, 200.0f);
    area.add(content);

    UiLayoutContext context;
    area.layout(context);

    assert(area.maxScrollX() == 100.0f);
    assert(area.maxScrollY() == 120.0f);
    assert(area.horizontalThumbWidth() == 50.0f);
    assert(area.verticalThumbHeight() == 32.0f);

    area.scrollTo(50.0f, 60.0f);
    assert(area.horizontalThumbLeft() == 25.0f);
    assert(area.verticalThumbTop() == 24.0f);
}

@("UiScrollArea clips child panel geometry to its viewport")
unittest
{
    auto area = new UiScrollArea(0.0f, 0.0f, 100.0f, 80.0f);
    auto content = new UiFrameBox(0.0f, 0.0f, 100.0f, 160.0f, [0.1f, 0.2f, 0.3f, 1.0f], [0.4f, 0.5f, 0.6f, 1.0f]);
    content.setLayoutHint(100.0f, 160.0f, 100.0f, 160.0f);
    area.add(content);

    UiLayoutContext layoutContext;
    area.layout(layoutContext);

    Vertex[] panels;
    UiRenderContext renderContext;
    renderContext.extentWidth = 200.0f;
    renderContext.extentHeight = 200.0f;
    renderContext.panels = &panels;
    area.render(renderContext);

    assert(panels.length > 0);
    float maxPixelY = 0.0f;
    foreach (vertex; panels)
    {
        const pixelY = (vertex.position[1] + 1.0f) * 0.5f * renderContext.extentHeight;
        if (pixelY > maxPixelY)
            maxPixelY = pixelY;
    }
    assert(maxPixelY <= 80.001f);
}

/** Vertical stack container. */
final class UiVBox : UiLayoutContainer
{
    float spacing;

    this(float x = 0.0f, float y = 0.0f, float width = 0.0f, float height = 0.0f, float spacing = 0.0f, float paddingLeft = 0.0f, float paddingTop = 0.0f, float paddingRight = 0.0f, float paddingBottom = 0.0f)
    {
        super(x, y, width, height, paddingLeft, paddingTop, paddingRight, paddingBottom);
        this.spacing = spacing;
    }

protected:
    override UiLayoutSize measureSelf(ref UiLayoutContext context)
    {
        float widest = 0.0f;
        float totalHeight = 0.0f;

        foreach (index, child; children)
        {
            const childSize = child.measure(context);
            if (childSize.width > widest)
                widest = childSize.width;
            totalHeight += childSize.height;
            if (index + 1 < children.length)
                totalHeight += spacing;
        }

        return UiLayoutSize(preferredWidth > 0.0f ? preferredWidth : widest + paddingLeft + paddingRight, preferredHeight > 0.0f ? preferredHeight : totalHeight + paddingTop + paddingBottom);
    }

    override void layoutChildren()
    {
        float cursorY = paddingTop;
        const availableWidth = innerWidth();
        const childCount = children.length;
        const availableHeight = max(innerHeight() - spacing * cast(float)(childCount > 0 ? childCount - 1 : 0), 0.0f);
        auto childHeights = resolveSizes(children, availableHeight, false);

        foreach (index, child; children)
        {
            const hint = horizontalHint(child);
            const childWidth = hint.grow > 0.0f ? clampFloat(availableWidth, hint.minimum > 0.0f ? hint.minimum : 0.0f, hint.maximum) : clampFloat(hint.preferred > 0.0f ? hint.preferred : availableWidth, hint.minimum > 0.0f ? hint.minimum : 0.0f, hint.maximum);
            child.x = paddingLeft;
            child.y = cursorY;
            child.width = childWidth;
            child.height = childHeights[index];
            cursorY += child.height;
            cursorY += spacing;
        }
    }

    override void layoutSelf(ref UiLayoutContext context)
    {
        float cursorY = paddingTop;
        const availableWidth = innerWidth();
        const childCount = children.length;
        const availableHeight = max(innerHeight() - spacing * cast(float)(childCount > 0 ? childCount - 1 : 0), 0.0f);
        auto childHeights = resolveSizes(children, availableHeight, false);

        foreach (index, child; children)
        {
            const hint = horizontalHint(child);
            const childWidth = hint.grow > 0.0f ? clampFloat(availableWidth, hint.minimum > 0.0f ? hint.minimum : 0.0f, hint.maximum) : clampFloat(hint.preferred > 0.0f ? hint.preferred : availableWidth, hint.minimum > 0.0f ? hint.minimum : 0.0f, hint.maximum);
            child.x = paddingLeft;
            child.y = cursorY;
            child.width = childWidth;
            child.height = childHeights[index];
            child.layout(context);
            cursorY += child.height;
            cursorY += spacing;
        }
    }

    override float[4] debugBoundsColor() const
    {
        return cast(float[4])verticalLayoutDebugBoundsColor;
    }
}

/** Horizontal row container. */
final class UiHBox : UiLayoutContainer
{
    float spacing;

    this(float x = 0.0f, float y = 0.0f, float width = 0.0f, float height = 0.0f, float spacing = 0.0f, float paddingLeft = 0.0f, float paddingTop = 0.0f, float paddingRight = 0.0f, float paddingBottom = 0.0f)
    {
        super(x, y, width, height, paddingLeft, paddingTop, paddingRight, paddingBottom);
        this.spacing = spacing;
    }

protected:
    override UiLayoutSize measureSelf(ref UiLayoutContext context)
    {
        float widest = 0.0f;
        float totalWidth = 0.0f;

        foreach (index, child; children)
        {
            const childSize = child.measure(context);
            if (childSize.height > widest)
                widest = childSize.height;
            totalWidth += childSize.width;
            if (index + 1 < children.length)
                totalWidth += spacing;
        }

        return UiLayoutSize(preferredWidth > 0.0f ? preferredWidth : totalWidth + paddingLeft + paddingRight, preferredHeight > 0.0f ? preferredHeight : widest + paddingTop + paddingBottom);
    }

    override void layoutChildren()
    {
        float cursorX = paddingLeft;
        const availableHeight = innerHeight();
        const childCount = children.length;
        const availableWidth = max(innerWidth() - spacing * cast(float)(childCount > 0 ? childCount - 1 : 0), 0.0f);
        auto childWidths = resolveSizes(children, availableWidth, true);

        foreach (index, child; children)
        {
            const hint = verticalHint(child);
            const childHeight = hint.grow > 0.0f ? clampFloat(availableHeight, hint.minimum > 0.0f ? hint.minimum : 0.0f, hint.maximum) : clampFloat(hint.preferred > 0.0f ? hint.preferred : availableHeight, hint.minimum > 0.0f ? hint.minimum : 0.0f, hint.maximum);
            child.x = cursorX;
            child.y = paddingTop;
            child.width = childWidths[index];
            child.height = childHeight;
            cursorX += child.width;
            cursorX += spacing;
        }
    }

    override void layoutSelf(ref UiLayoutContext context)
    {
        float cursorX = paddingLeft;
        const availableHeight = innerHeight();
        const childCount = children.length;
        const availableWidth = max(innerWidth() - spacing * cast(float)(childCount > 0 ? childCount - 1 : 0), 0.0f);
        auto childWidths = resolveSizes(children, availableWidth, true);

        foreach (index, child; children)
        {
            const hint = verticalHint(child);
            const childHeight = hint.grow > 0.0f ? clampFloat(availableHeight, hint.minimum > 0.0f ? hint.minimum : 0.0f, hint.maximum) : clampFloat(hint.preferred > 0.0f ? hint.preferred : availableHeight, hint.minimum > 0.0f ? hint.minimum : 0.0f, hint.maximum);
            child.x = cursorX;
            child.y = paddingTop;
            child.width = childWidths[index];
            child.height = childHeight;
            child.layout(context);
            cursorX += child.width;
            cursorX += spacing;
        }
    }

    override float[4] debugBoundsColor() const
    {
        return cast(float[4])horizontalLayoutDebugBoundsColor;
    }
}

private struct GridPlacement
{
    size_t row;
    size_t column;
    size_t rowSpan;
    size_t columnSpan;
}

/** Simple weighted grid layout with explicit cell placement. */
final class UiGrid : UiLayoutContainer
{
    private GridPlacement[] placements;
    private float[] rowWeights;
    private float[] columnWeights;
    float spacingX;
    float spacingY;

    this(size_t rows, size_t columns, float x = 0.0f, float y = 0.0f, float width = 0.0f, float height = 0.0f, float spacingX = 0.0f, float spacingY = 0.0f, float paddingLeft = 0.0f, float paddingTop = 0.0f, float paddingRight = 0.0f, float paddingBottom = 0.0f)
    {
        super(x, y, width, height, paddingLeft, paddingTop, paddingRight, paddingBottom);
        this.spacingX = spacingX;
        this.spacingY = spacingY;
        rowWeights.length = rows;
        columnWeights.length = columns;
        rowWeights[] = 1.0f;
        columnWeights[] = 1.0f;
    }

    void add(UiWidget child, size_t row, size_t column, size_t rowSpan = 1, size_t columnSpan = 1)
    {
        if (child is null)
            return;

        child.parent = this;
        children ~= child;
        placements ~= GridPlacement(row, column, rowSpan, columnSpan);
    }

protected:
    override void layoutChildren()
    {
        if (children.length != placements.length)
            return;

        const totalWidth = innerWidth();
        const totalHeight = innerHeight();

        float columnWeightSum = 0.0f;
        foreach (weight; columnWeights)
            columnWeightSum += weight;

        float rowWeightSum = 0.0f;
        foreach (weight; rowWeights)
            rowWeightSum += weight;

        float[] columnOffsets;
        float[] rowOffsets;
        float[] columnSizes;
        float[] rowSizes;
        columnOffsets.length = columnWeights.length;
        rowOffsets.length = rowWeights.length;
        columnSizes.length = columnWeights.length;
        rowSizes.length = rowWeights.length;

        float usedWidth = 0.0f;
        foreach (index, weight; columnWeights)
        {
            const columnSize = columnWeightSum > 0.0f ? totalWidth * (weight / columnWeightSum) : 0.0f;
            columnSizes[index] = columnSize;
            columnOffsets[index] = usedWidth;
            usedWidth += columnSize + spacingX;
        }

        float usedHeight = 0.0f;
        foreach (index, weight; rowWeights)
        {
            const rowSize = rowWeightSum > 0.0f ? totalHeight * (weight / rowWeightSum) : 0.0f;
            rowSizes[index] = rowSize;
            rowOffsets[index] = usedHeight;
            usedHeight += rowSize + spacingY;
        }

        foreach (index, child; children)
        {
            const placement = placements[index];
            const childX = paddingLeft + columnOffsets[placement.column];
            const childY = paddingTop + rowOffsets[placement.row];

            float childWidth = 0.0f;
            for (size_t column = placement.column; column < placement.column + placement.columnSpan && column < columnSizes.length; ++column)
                childWidth += columnSizes[column];
            if (placement.columnSpan > 1)
                childWidth += spacingX * cast(float)(placement.columnSpan - 1);

            float childHeight = 0.0f;
            for (size_t row = placement.row; row < placement.row + placement.rowSpan && row < rowSizes.length; ++row)
                childHeight += rowSizes[row];
            if (placement.rowSpan > 1)
                childHeight += spacingY * cast(float)(placement.rowSpan - 1);

            child.x = childX;
            child.y = childY;
            if (child.width <= 0.0f)
                child.width = childWidth;
            if (child.height <= 0.0f)
                child.height = childHeight;
        }
    }

    override float[4] debugBoundsColor() const
    {
        return cast(float[4])gridLayoutDebugBoundsColor;
    }
}
