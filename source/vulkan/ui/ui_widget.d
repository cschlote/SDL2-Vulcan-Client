/** Base element for retained UI widgets.
 *
 * Widgets share layout, visibility, and recursive rendering behavior through
 * this common base class.
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.ui.ui_widget;

import vulkan.ui.ui_event : UiPointerEvent;
import vulkan.ui.ui_context : UiRenderContext;
import vulkan.ui.ui_layout_context : UiLayoutContext, UiLayoutSize;
import vulkan.ui.ui_widget_helpers : appendSurfaceFrame;

private immutable float[4] widgetDebugBoundsColor = [1.00f, 0.05f, 0.05f, 0.55f];

/** Base class for all retained UI widgets. */
abstract class UiWidget
{
    float x;
    float y;
    float width;
    float height;
    float minimumWidth;
    float minimumHeight;
    float preferredWidth;
    float preferredHeight;
    float maximumWidth;
    float maximumHeight;
    float flexGrowX;
    float flexGrowY;
    float childOffsetX;
    float childOffsetY;
    bool visible = true;
    UiWidget[] children;

    this(float x = 0, float y = 0, float width = 0, float height = 0)
    {
        this.x = x;
        this.y = y;
        this.width = width;
        this.height = height;
        minimumWidth = width;
        minimumHeight = height;
        preferredWidth = width;
        preferredHeight = height;
        maximumWidth = float.max;
        maximumHeight = float.max;
        flexGrowX = 0.0f;
        flexGrowY = 0.0f;
        childOffsetX = 0.0f;
        childOffsetY = 0.0f;
    }

    /** Adds a child widget below this widget in the visual tree. */
    void add(UiWidget child)
    {
        children ~= child;
    }

    /** Updates the widget's layout hint independently from its final frame. */
    void setLayoutHint(float minimumWidth, float minimumHeight, float preferredWidth, float preferredHeight, float maximumWidth = float.max, float maximumHeight = float.max, float flexGrowX = 0.0f, float flexGrowY = 0.0f)
    {
        this.minimumWidth = minimumWidth;
        this.minimumHeight = minimumHeight;
        this.preferredWidth = preferredWidth;
        this.preferredHeight = preferredHeight;
        this.maximumWidth = maximumWidth;
        this.maximumHeight = maximumHeight;
        this.flexGrowX = flexGrowX;
        this.flexGrowY = flexGrowY;
    }

    /** Measures the widget's intrinsic size for a layout pass. */
    final UiLayoutSize measure(ref UiLayoutContext context)
    {
        const measured = measureSelf(context);
        if (preferredWidth <= 0.0f)
            preferredWidth = measured.width;
        if (preferredHeight <= 0.0f)
            preferredHeight = measured.height;
        if (minimumWidth <= 0.0f)
            minimumWidth = measured.width;
        if (minimumHeight <= 0.0f)
            minimumHeight = measured.height;
        return measured;
    }

    /** Runs an explicit layout pass for the widget subtree. */
    final void layout(ref UiLayoutContext context)
    {
        const measured = measure(context);
        if (width <= 0.0f)
            width = measured.width;
        if (height <= 0.0f)
            height = measured.height;

        layoutSelf(context);
    }

    /** Routes a pointer event through the widget tree. */
    bool dispatchPointerEvent(ref UiPointerEvent event)
    {
        if (!visible)
            return false;

        if (width > 0.0f && height > 0.0f && !contains(event.x, event.y))
            return false;

        auto childEvent = event;
        childEvent.x -= x + childOffsetX;
        childEvent.y -= y + childOffsetY;

        for (ptrdiff_t index = cast(ptrdiff_t)children.length - 1; index >= 0; --index)
        {
            if (children[cast(size_t)index].dispatchPointerEvent(childEvent))
                return true;
        }

        return handlePointerEvent(event);
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
            childContext.depthBase = localContext.depthBase - cast(float)(index + 1) * 0.001f;
            child.render(childContext);
        }

        if (context.debugWidgetBounds && width > 0.0f && height > 0.0f)
        {
            const color = debugBoundsColor();
            appendSurfaceFrame(localContext, 0.0f, 0.0f, width, height, color, color, localContext.depthBase - 0.0005f, false, true);
        }
    }

protected:
    /** Returns the widget's intrinsic size before a layout pass positions it. */
    UiLayoutSize measureSelf(ref UiLayoutContext context)
    {
        return UiLayoutSize(preferredWidth > 0.0f ? preferredWidth : width, preferredHeight > 0.0f ? preferredHeight : height);
    }

    /** Positions the widget's children during an explicit layout pass. */
    void layoutSelf(ref UiLayoutContext context)
    {
    }

    abstract void renderSelf(ref UiRenderContext context);

    /** Returns the debug bounds color for this widget type. */
    float[4] debugBoundsColor() const
    {
        return cast(float[4])widgetDebugBoundsColor;
    }

    /** Handles a pointer event after children had a chance to consume it. */
    bool handlePointerEvent(ref UiPointerEvent event)
    {
        return false;
    }

    /** Returns whether the event hits the widget body in parent space. */
    bool contains(float localX, float localY) const
    {
        return localX >= x && localY >= y && localX < x + width && localY < y + height;
    }
}
