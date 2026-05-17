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

import vulkan.ui.ui_event : UiKeyEvent, UiPointerEvent, UiTextInputEvent;
import vulkan.ui.ui_context : UiRenderContext;
import vulkan.ui.ui_cursor : UiCursorKind;
import vulkan.ui.ui_layout_context : UiLayoutContext, UiLayoutSize;
import vulkan.ui.ui_widget_helpers : appendSurfaceFrame;

private immutable float[4] widgetDebugBoundsColor = [1.00f, 0.05f, 0.05f, 0.55f];
private immutable float[4] widgetFocusRingColor = [0.34f, 0.82f, 0.46f, 0.95f];

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
    bool focusable;
    bool focused;
    string tooltipText;
    UiWidget parent;
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
        if (child is null)
            return;

        child.parent = this;
        children ~= child;
    }

    /** Returns the widget left edge in screen coordinates. */
    float screenX()
    {
        float result = x;
        UiWidget owner = parent;
        while (owner !is null)
        {
            result += owner.x + owner.childOffsetX;
            owner = owner.parent;
        }
        return result;
    }

    /** Returns the widget top edge in screen coordinates. */
    float screenY()
    {
        float result = y;
        UiWidget owner = parent;
        while (owner !is null)
        {
            result += owner.y + owner.childOffsetY;
            owner = owner.parent;
        }
        return result;
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
            {
                event.actionActivated = event.actionActivated || childEvent.actionActivated;
                return true;
            }
        }

        auto localEvent = event;
        localEvent.x -= x;
        localEvent.y -= y;
        const handled = handlePointerEvent(localEvent);
        event.actionActivated = event.actionActivated || localEvent.actionActivated;
        return handled;
    }

    /** Returns the deepest focusable widget at the given point in parent space. */
    UiWidget focusTargetAt(float localX, float localY)
    {
        if (!visible)
            return null;

        if (width > 0.0f && height > 0.0f && !contains(localX, localY))
            return null;

        const childX = localX - x - childOffsetX;
        const childY = localY - y - childOffsetY;

        for (ptrdiff_t index = cast(ptrdiff_t)children.length - 1; index >= 0; --index)
        {
            auto target = children[cast(size_t)index].focusTargetAt(childX, childY);
            if (target !is null)
                return target;
        }

        return focusable ? this : null;
    }

    /** Returns the cursor intent at the given point in parent space. */
    UiCursorKind cursorAt(float localX, float localY)
    {
        if (!visible)
            return UiCursorKind.default_;

        if (width > 0.0f && height > 0.0f && !contains(localX, localY))
            return UiCursorKind.default_;

        const childX = localX - x - childOffsetX;
        const childY = localY - y - childOffsetY;

        for (ptrdiff_t index = cast(ptrdiff_t)children.length - 1; index >= 0; --index)
        {
            const cursor = children[cast(size_t)index].cursorAt(childX, childY);
            if (cursor != UiCursorKind.default_)
                return cursor;
        }

        return cursorSelf(localX, localY);
    }

    /** Returns the tooltip text at the given point in parent space, or empty. */
    string tooltipAt(float localX, float localY)
    {
        if (!visible)
            return "";

        if (width > 0.0f && height > 0.0f && !contains(localX, localY))
            return "";

        const childX = localX - x - childOffsetX;
        const childY = localY - y - childOffsetY;

        for (ptrdiff_t index = cast(ptrdiff_t)children.length - 1; index >= 0; --index)
        {
            const tooltip = children[cast(size_t)index].tooltipAt(childX, childY);
            if (tooltip.length != 0)
                return tooltip;
        }

        return tooltipSelf(localX, localY);
    }

    /** Updates the widget focus flag. Screens call this when focus ownership changes. */
    void setFocused(bool focused)
    {
        this.focused = focused;
    }

    /** Routes a keyboard event to this widget. */
    bool dispatchKeyEvent(ref UiKeyEvent event)
    {
        if (!visible)
            return false;

        return handleKeyEvent(event);
    }

    /** Routes UTF-8 text input to this widget. */
    bool dispatchTextInputEvent(ref UiTextInputEvent event)
    {
        if (!visible)
            return false;

        return handleTextInputEvent(event);
    }

    /** Advances optional widget-local animation state for this subtree.
     *
     * Returns true when rendering another UI frame is useful even without new
     * input.
     */
    final bool tick(float deltaSeconds)
    {
        if (!visible)
            return false;

        bool dirty = tickSelf(deltaSeconds);
        if (!visible)
            return dirty;

        foreach (child; children)
            dirty = child.tick(deltaSeconds) || dirty;

        return dirty;
    }

    /** Renders the widget and its children in back-to-front order. */
    final void render(ref UiRenderContext context)
    {
        if (!visible)
            return;

        auto localContext = context.offset(x, y);
        renderSelf(localContext);

        auto childContext = childRenderContext(localContext.offset(childOffsetX, childOffsetY));
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

        if (focused && focusable && width > 0.0f && height > 0.0f)
            appendSurfaceFrame(localContext, 1.0f, 1.0f, width - 1.0f, height - 1.0f, widgetFocusRingColor, widgetFocusRingColor, localContext.depthBase - 0.004f, false, true);
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

    /** Allows containers to alter the render context used for children. */
    UiRenderContext childRenderContext(UiRenderContext context)
    {
        return context;
    }

    /** Returns the debug bounds color for this widget type. */
    float[4] debugBoundsColor() const
    {
        return cast(float[4])widgetDebugBoundsColor;
    }

    /** Returns this widget's own cursor intent after children were checked. */
    UiCursorKind cursorSelf(float localX, float localY)
    {
        return UiCursorKind.default_;
    }

    /** Returns this widget's own tooltip text after children were checked. */
    string tooltipSelf(float localX, float localY)
    {
        return tooltipText;
    }

    /** Handles a pointer event after children had a chance to consume it. */
    bool handlePointerEvent(ref UiPointerEvent event)
    {
        return false;
    }

    /** Handles a keyboard event when the widget owns focus. */
    bool handleKeyEvent(ref UiKeyEvent event)
    {
        return false;
    }

    /** Handles UTF-8 text input when the widget owns focus. */
    bool handleTextInputEvent(ref UiTextInputEvent event)
    {
        return false;
    }

    /** Advances this widget's own animation state. */
    bool tickSelf(float deltaSeconds)
    {
        return false;
    }

    /** Returns whether the event hits the widget body in parent space. */
    bool contains(float localX, float localY) const
    {
        return localX >= x && localY >= y && localX < x + width && localY < y + height;
    }
}

@("UiWidget ticks visible subtrees and reports animation dirtiness")
unittest
{
    final class TickWidget : UiWidget
    {
        float lastDelta;
        uint tickCount;
        bool dirty;

        this(bool dirty = false)
        {
            super(0.0f, 0.0f, 10.0f, 10.0f);
            this.dirty = dirty;
        }

    protected:
        override void renderSelf(ref UiRenderContext context)
        {
        }

        override bool tickSelf(float deltaSeconds)
        {
            lastDelta = deltaSeconds;
            tickCount++;
            return dirty;
        }
    }

    auto root = new TickWidget();
    auto child = new TickWidget(true);
    auto hiddenChild = new TickWidget(true);
    hiddenChild.visible = false;
    root.add(child);
    root.add(hiddenChild);

    assert(root.tick(0.025f));
    assert(root.tickCount == 1);
    assert(child.tickCount == 1);
    assert(hiddenChild.tickCount == 0);
    assert(child.lastDelta == 0.025f);
}

@("UiWidget reports screen coordinates through parent offsets")
unittest
{
    final class PositionWidget : UiWidget
    {
        this(float x = 0.0f, float y = 0.0f)
        {
            super(x, y, 10.0f, 10.0f);
        }

    protected:
        override void renderSelf(ref UiRenderContext context)
        {
        }
    }

    auto root = new PositionWidget(100.0f, 50.0f);
    root.childOffsetX = 4.0f;
    root.childOffsetY = 6.0f;

    auto group = new PositionWidget(20.0f, 10.0f);
    group.childOffsetX = 2.0f;
    group.childOffsetY = 3.0f;

    auto child = new PositionWidget(7.0f, 5.0f);

    root.add(group);
    group.add(child);

    assert(child.screenX() == 133.0f);
    assert(child.screenY() == 74.0f);
}

@("UiWidget dispatches own pointer events in widget-local coordinates")
unittest
{
    final class PointerWidget : UiWidget
    {
        float lastX;
        float lastY;

        this(float x = 0.0f, float y = 0.0f)
        {
            super(x, y, 20.0f, 20.0f);
        }

    protected:
        override void renderSelf(ref UiRenderContext context)
        {
        }

        override bool handlePointerEvent(ref UiPointerEvent event)
        {
            lastX = event.x;
            lastY = event.y;
            return true;
        }
    }

    auto root = new PointerWidget();
    root.width = 100.0f;
    root.height = 100.0f;
    auto child = new PointerWidget(30.0f, 40.0f);
    root.add(child);

    UiPointerEvent event;
    event.x = 35.0f;
    event.y = 46.0f;

    assert(root.dispatchPointerEvent(event));
    assert(child.lastX == 5.0f);
    assert(child.lastY == 6.0f);
}
