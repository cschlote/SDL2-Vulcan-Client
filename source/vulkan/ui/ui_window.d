/** Retained window widget with title bar and content region.
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.ui.ui_window;

import vulkan.ui.ui_event : UiPointerEvent, UiPointerEventKind;
import vulkan.ui.ui_context : UiRenderContext, UiTextStyle;
import vulkan.ui.ui_container : UiContainer;
import vulkan.ui.ui_widget : UiWidget;
import vulkan.ui.ui_widget_helpers : appendButtonFrame, appendTextLine, appendWindowFrame;

/** Simple retained window with a title bar and a content region. */
final class UiWindow : UiWidget
{
    string title;
    float[4] bodyColor;
    float[4] headerColor;
    float[4] titleColor;
    float headerHeight = 7.0f;
    bool resizable;
    bool dragTracking;
    bool resizeTracking;
    private UiContainer contentRoot;
    void delegate(float, float) onHeaderDragStart;
    void delegate(float, float) onHeaderDragMove;
    void delegate() onHeaderDragEnd;
    void delegate() onResizeStart;
    void delegate(float, float) onResizeMove;
    void delegate() onResizeEnd;

    this(string title, float x, float y, float width, float height, float[4] bodyColor, float[4] headerColor, float[4] titleColor, bool resizable = false)
    {
        super(x, y, width, height);
        this.title = title;
        this.bodyColor = bodyColor;
        this.headerColor = headerColor;
        this.titleColor = titleColor;
        this.resizable = resizable;
        contentRoot = new UiContainer();
        super.add(contentRoot);
        childOffsetX = 18.0f;
        childOffsetY = 36.0f;
    }

    override void add(UiWidget child)
    {
        contentRoot.add(child);
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

        if (resizable && resizeTracking)
        {
            if (event.kind == UiPointerEventKind.move)
            {
                if (onResizeMove !is null)
                    onResizeMove(event.x, event.y);
                return true;
            }

            if (event.kind == UiPointerEventKind.buttonUp && event.button == 1)
            {
                if (onResizeEnd !is null)
                    onResizeEnd();
                resizeTracking = false;
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

        if (resizable && event.kind == UiPointerEventKind.buttonDown && event.button == 1 && isInResizeGrip(event.x, event.y))
        {
            if (onResizeStart !is null)
                onResizeStart();
            resizeTracking = true;
            dragTracking = false;
            return true;
        }

        if (event.kind == UiPointerEventKind.buttonDown && event.button == 1 && isInHeader(event.x, event.y))
        {
            if (onHeaderDragStart !is null)
                onHeaderDragStart(event.x, event.y);
            dragTracking = true;
            resizeTracking = false;
            return true;
        }

        return handlePointerEvent(event);
    }

protected:
    override void renderSelf(ref UiRenderContext context)
    {
        appendWindowFrame(context, 0.0f, 0.0f, width, height, headerHeight, bodyColor, headerColor, context.depthBase);
        appendTextLine(context, UiTextStyle.medium, title, 12.0f, 6.0f, titleColor, context.depthBase - 0.001f);
        if (resizable)
            appendButtonFrame(context, width - 16.0f, height - 16.0f, width - 2.0f, height - 2.0f, [0.14f, 0.16f, 0.20f, 0.88f], [0.20f, 0.56f, 0.98f, 0.92f], context.depthBase - 0.0005f);
    }

private:
    bool isInHeader(float localX, float localY) const
    {
        return localX >= x && localY >= y && localX < x + width && localY < y + headerHeight;
    }

    bool isInResizeGrip(float localX, float localY) const
    {
        return localX >= x + width - 16.0f && localY >= y + height - 16.0f && localX < x + width && localY < y + height;
    }
}
