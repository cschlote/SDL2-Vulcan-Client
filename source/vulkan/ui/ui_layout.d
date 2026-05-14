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

import vulkan.ui.ui_context : UiRenderContext;
import vulkan.ui.ui_event : UiPointerEvent;
import vulkan.ui.ui_widget_helpers : appendSurfaceFrame;
import vulkan.ui.ui_widget : UiWidget;

/** Invisible widget that only contributes space to a layout. */
final class UiSpacer : UiWidget
{
    this(float width = 0.0f, float height = 0.0f)
    {
        super(0.0f, 0.0f, width, height);
    }

protected:
    override void renderSelf(ref UiRenderContext context)
    {
    }

    override bool dispatchPointerEvent(ref UiPointerEvent event)
    {
        return false;
    }
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
    override void renderSelf(ref UiRenderContext context)
    {
        appendSurfaceFrame(context, 0.0f, 0.0f, width, height, backgroundColor, borderColor, context.depthBase, drawBackground, drawBorder);
        layoutChildren();
    }

    override void layoutChildren()
    {
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
    override void layoutChildren()
    {
        float cursorY = paddingTop;
        const availableWidth = innerWidth();

        foreach (child; children)
        {
            if (child.width <= 0.0f)
                child.width = availableWidth;
            child.x = paddingLeft;
            child.y = cursorY;
            cursorY += child.height;
            cursorY += spacing;
        }
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
    override void layoutChildren()
    {
        float cursorX = paddingLeft;
        const availableHeight = innerHeight();

        foreach (child; children)
        {
            if (child.height <= 0.0f)
                child.height = availableHeight;
            child.x = cursorX;
            child.y = paddingTop;
            cursorX += child.width;
            cursorX += spacing;
        }
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
}
