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
import vulkan.ui.ui_context : UiRenderContext;
import vulkan.ui.ui_event : UiPointerEvent, UiPointerEventKind;
import vulkan.ui.ui_layout_context : UiLayoutContext, UiLayoutSize;
import vulkan.ui.ui_widget_helpers : appendSurfaceFrame;
import vulkan.ui.ui_widget : UiWidget;

private immutable float[4] contentBoxDebugBoundsColor = [0.15f, 0.95f, 1.00f, 0.65f];
private immutable float[4] verticalLayoutDebugBoundsColor = [0.20f, 1.00f, 0.35f, 0.65f];
private immutable float[4] horizontalLayoutDebugBoundsColor = [0.20f, 0.50f, 1.00f, 0.65f];
private immutable float[4] gridLayoutDebugBoundsColor = [0.90f, 0.30f, 1.00f, 0.65f];
private immutable float[4] spacerDebugBoundsColor = [1.00f, 1.00f, 0.20f, 0.45f];
private immutable float[4] scrollAreaDebugBoundsColor = [1.00f, 0.72f, 0.18f, 0.65f];

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
