/** Retained window widget with title bar and content region.
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.ui.ui_window;

import vulkan.ui.ui_event : UiPointerEvent, UiPointerEventKind;
import vulkan.ui.ui_context : UiRenderContext, UiTextStyle;
import vulkan.ui.ui_widget : UiWidget;
import vulkan.ui.ui_widget_helpers : appendTextLine, appendWindowFrame;

/** Simple retained window with a title bar and a content region. */
final class UiWindow : UiWidget
{
    string title;
    float[4] bodyColor;
    float[4] headerColor;
    float[4] titleColor;
    float headerHeight = 7.0f;
    bool dragTracking;
    void delegate(float, float) onHeaderDragStart;
    void delegate(float, float) onHeaderDragMove;
    void delegate() onHeaderDragEnd;

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

    override bool dispatchPointerEvent(ref UiPointerEvent event)
    {
        if (!visible)
            return false;

        if (dragTracking)
        {
            if (event.kind == UiPointerEventKind.move)
            {
                if (onHeaderDragMove !is null)
                    onHeaderDragMove(event.x, event.y);
                return true;
            }

            if (event.kind == UiPointerEventKind.buttonUp && event.button == 1)
            {
                if (onHeaderDragEnd !is null)
                    onHeaderDragEnd();
                dragTracking = false;
                return true;
            }
        }

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

        if (event.kind == UiPointerEventKind.buttonDown && event.button == 1 && isInHeader(event.x, event.y))
        {
            if (onHeaderDragStart !is null)
                onHeaderDragStart(event.x, event.y);
            dragTracking = true;
            return true;
        }

        return handlePointerEvent(event);
    }

protected:
    override void renderSelf(ref UiRenderContext context)
    {
        appendWindowFrame(context, 0.0f, 0.0f, width, height, headerHeight, bodyColor, headerColor, context.depthBase);
        appendTextLine(context, UiTextStyle.medium, title, 12.0f, 6.0f, titleColor, context.depthBase - 0.001f);
    }

private:
    bool isInHeader(float localX, float localY) const
    {
        return localX >= x && localY >= y && localX < x + width && localY < y + headerHeight;
    }
}
