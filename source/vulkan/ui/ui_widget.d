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

/** Base class for all retained UI widgets. */
abstract class UiWidget
{
    float x;
    float y;
    float width;
    float height;
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
        childOffsetX = 0.0f;
        childOffsetY = 0.0f;
    }

    /** Adds a child widget below this widget in the visual tree. */
    void add(UiWidget child)
    {
        children ~= child;
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
            childContext.depthBase = localContext.depthBase - cast(float)index * 0.001f;
            child.render(childContext);
        }
    }

protected:
    abstract void renderSelf(ref UiRenderContext context);

    /** Handles a pointer event after children had a chance to consume it. */
    bool handlePointerEvent(ref UiPointerEvent event)
    {
        return false;
    }

protected:
    /** Returns whether the event hits the widget body in parent space. */
    bool contains(float localX, float localY) const
    {
        return localX >= x && localY >= y && localX < x + width && localY < y + height;
    }
}
