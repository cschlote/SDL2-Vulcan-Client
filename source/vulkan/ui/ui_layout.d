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
import vulkan.ui.ui_event : UiPointerEvent;
import vulkan.ui.ui_layout_context : UiLayoutContext, UiLayoutSize;
import vulkan.ui.ui_widget_helpers : appendSurfaceFrame;
import vulkan.ui.ui_widget : UiWidget;

private immutable float[4] surfaceDebugBoundsColor = [0.15f, 0.95f, 1.00f, 0.65f];
private immutable float[4] verticalLayoutDebugBoundsColor = [0.20f, 1.00f, 0.35f, 0.65f];
private immutable float[4] horizontalLayoutDebugBoundsColor = [0.20f, 0.50f, 1.00f, 0.65f];
private immutable float[4] gridLayoutDebugBoundsColor = [0.90f, 0.30f, 1.00f, 0.65f];
private immutable float[4] spacerDebugBoundsColor = [1.00f, 1.00f, 0.20f, 0.45f];

/** Invisible widget that only contributes space to a layout. */
final class UiSpacer : UiWidget
{
    this(float width = 0.0f, float height = 0.0f)
    {
        super(0.0f, 0.0f, width, height);
    }

protected:
    override UiLayoutSize measureSelf(ref UiLayoutContext context)
    {
        return UiLayoutSize(width, height);
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
    hint.minimum = child.minimumWidth > 0.0f ? child.minimumWidth : child.preferredWidth > 0.0f ? child.preferredWidth : child.width;
    hint.preferred = child.preferredWidth > 0.0f ? child.preferredWidth : child.width;
    hint.maximum = child.maximumWidth > 0.0f ? child.maximumWidth : float.max;
    hint.grow = child.flexGrowX;
    return hint;
}

private AxisHint verticalHint(UiWidget child)
{
    AxisHint hint;
    hint.minimum = child.minimumHeight > 0.0f ? child.minimumHeight : child.preferredHeight > 0.0f ? child.preferredHeight : child.height;
    hint.preferred = child.preferredHeight > 0.0f ? child.preferredHeight : child.height;
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

/** Box-style layout container with optional background and border. */
final class UiSurfaceBox : UiLayoutContainer
{
    float[4] backgroundColor;
    float[4] borderColor;
    bool drawBorder = true;
    bool drawBackground = true;

    this(float x = 0.0f, float y = 0.0f, float width = 0.0f, float height = 0.0f, float[4] backgroundColor = [0.0f, 0.0f, 0.0f, 0.0f], float[4] borderColor = [0.0f, 0.0f, 0.0f, 0.0f], float paddingLeft = 0.0f, float paddingTop = 0.0f, float paddingRight = 0.0f, float paddingBottom = 0.0f)
    {
        super(x, y, width, height, paddingLeft, paddingTop, paddingRight, paddingBottom);
        this.backgroundColor = backgroundColor;
        this.borderColor = borderColor;
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

        const measuredWidth = width > 0.0f ? width : widest + paddingLeft + paddingRight;
        const measuredHeight = height > 0.0f ? height : tallest + paddingTop + paddingBottom;
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
        return cast(float[4])surfaceDebugBoundsColor;
    }
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

        return UiLayoutSize(width > 0.0f ? width : widest + paddingLeft + paddingRight, height > 0.0f ? height : totalHeight + paddingTop + paddingBottom);
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

        return UiLayoutSize(width > 0.0f ? width : totalWidth + paddingLeft + paddingRight, height > 0.0f ? height : widest + paddingTop + paddingBottom);
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
