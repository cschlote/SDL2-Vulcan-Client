/** Retained window widget with title bar, content region, and chrome helpers.
 *
 * The window keeps the content tree separate from the chrome so the caller can
 * keep using ordinary retained widgets for the body while the window class
 * owns title emphasis, drag/resize affordances, close handling, and header
 * layout composition.
 */
module vulkan.ui.ui_window;

import std.algorithm : max;

import vulkan.ui.ui_button : UiButton;
import vulkan.ui.ui_context : UiRenderContext, UiTextStyle;
import vulkan.ui.ui_event : UiPointerEvent, UiPointerEventKind, UiResizeHandle;
import vulkan.ui.ui_layout_context : UiLayoutContext;
import vulkan.ui.ui_layout : UiHBox, UiSurfaceBox;
import vulkan.ui.ui_widget : UiWidget;
import vulkan.ui.ui_widget_helpers : appendButtonFrame, appendTextLine, appendWindowBorder, appendWindowFrame;
import logging : logLine, logLineVerbose;

private immutable float[4] windowDebugBoundsColor = [1.00f, 0.20f, 0.05f, 0.70f];

/** Retained window chrome with optional close, drag, and resize behavior. */
final class UiWindow : UiWidget
{
    string title;                                   ///< Window caption shown in the highlighted title badge.
    float[4] bodyColor;                             ///< Fill color for the window body.
    float[4] headerColor;                           ///< Base header color used when the window is not dragable.
    float[4] titleColor;                            ///< Text color for the highlighted title badge.
    bool sizeable;                                  ///< True when the window can be resized from its corners.
    bool closable;                                  ///< True when the window exposes a close button in the header.
    bool dragable;                                  ///< True when the header indicates drag support and accepts drag gestures.
    bool dragTracking;                              ///< True while a drag gesture is active.
    bool resizeTracking;                            ///< True while a resize gesture is active.
    UiResizeHandle resizeHandle = UiResizeHandle.none; ///< Active resize corner while a resize gesture is running.
    float headerHeight = 26.0f;                     ///< Height of the decorative header bar.

    private UiSurfaceBox contentRoot;               ///< Body widgets are kept in a separate root so chrome stays explicit.
    private UiHBox headerExtras;                    ///< Optional extra header widgets placed to the left of the close button.
    private UiButton closeButton;                   ///< Optional close button rendered in the header.
    private float headerExtrasWidth;                ///< Cached width of all extra header widgets.
    private float headerExtrasHeight;               ///< Cached height of all extra header widgets.

    void delegate(float, float) onHeaderDragStart;              ///< Notified when a header drag starts.
    void delegate(float, float) onHeaderDragMove;               ///< Notified while a header drag is running.
    void delegate() onHeaderDragEnd;                            ///< Notified when a header drag ends.
    void delegate(UiResizeHandle) onResizeStart;                ///< Notified when a resize gesture starts.
    void delegate(UiResizeHandle, float, float) onResizeMove;   ///< Notified while a resize gesture is running.
    void delegate(UiResizeHandle) onResizeEnd;                  ///< Notified when a resize gesture ends.
    void delegate() onClose;                                    ///< Notified when the built-in close button is activated.

    /**
     * Creates a retained window with explicit chrome flags.
     *
     * Params:
     *   title = Window title shown in the highlighted badge.
     *   x = Left edge in parent coordinates.
     *   y = Top edge in parent coordinates.
     *   width = Window width in pixels.
     *   height = Window height in pixels.
     *   bodyColor = Window body fill color.
     *   headerColor = Base header color used when the window is not dragable.
     *   titleColor = Title text color.
     *   sizeable = Enables the four resize corner grips.
     *   closable = Shows a close button in the header.
     *   dragable = Makes the header visually distinct and accepts drag gestures.
     */
    this(string title, float x, float y, float width, float height, float[4] bodyColor, float[4] headerColor, float[4] titleColor, bool sizeable = false, bool closable = false, bool dragable = false, float contentPaddingLeft = 18.0f, float contentPaddingTop = 10.0f, float contentPaddingRight = 18.0f, float contentPaddingBottom = 10.0f)
    {
        super(x, y, width, height);
        this.title = title;
        this.bodyColor = bodyColor;
        this.headerColor = headerColor;
        this.titleColor = titleColor;
        this.sizeable = sizeable;
        this.closable = closable;
        this.dragable = dragable;

        contentRoot = new UiSurfaceBox(0.0f, headerHeight, width, max(height - headerHeight, 0.0f), [0.0f, 0.0f, 0.0f, 0.0f], [0.0f, 0.0f, 0.0f, 0.0f], contentPaddingLeft, contentPaddingTop, contentPaddingRight, contentPaddingBottom);
        contentRoot.drawBackground = false;
        contentRoot.drawBorder = false;
        super.add(contentRoot);

        headerExtras = new UiHBox(0.0f, 0.0f, 0.0f, 0.0f, 4.0f);

        if (closable)
        {
            closeButton = new UiButton("X", 0.0f, 0.0f, 16.0f, 16.0f, [0.55f, 0.10f, 0.12f, 0.96f], [0.92f, 0.46f, 0.46f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f], UiTextStyle.small, 4.0f, 0.5f);
            closeButton.onClick = &handleCloseButton;
        }

        childOffsetX = 0.0f;
        childOffsetY = 0.0f;
    }

    /** Adds a child widget to the window body. */
    override void add(UiWidget child)
    {
        contentRoot.add(child);
    }

    /** Adds a widget to the header layout, left of the built-in close button. */
    void addHeaderWidget(UiWidget child)
    {
        headerExtras.add(child);
        refreshHeaderMetrics();
    }

    /** Alias for callers that prefer header-button terminology. */
    void addHeaderButton(UiWidget child)
    {
        addHeaderWidget(child);
    }

    /** Lays out the window body before rendering or hit testing.
     *
     * Params:
     *   context = Layout context used to measure text and nested widgets.
     * Returns:
     *   Nothing.
     */
    void layoutWindow(ref UiLayoutContext context)
    {
        updateChromeLayout();

        foreach (child; contentRoot.children)
            child.layout(context);
    }

    /** Routes pointer events through the chrome before the body content. */
    override bool dispatchPointerEvent(ref UiPointerEvent event)
    {
        if (!visible)
            return false;

        updateChromeLayout();

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
                logLine("UiWindow drag end: ", title);
                dragTracking = false;
                return true;
            }
        }

        if (resizeTracking)
        {
            if (event.kind == UiPointerEventKind.move)
            {
                if (onResizeMove !is null)
                    onResizeMove(resizeHandle, event.x, event.y);
                return true;
            }

            if (event.kind == UiPointerEventKind.buttonUp && event.button == 1)
            {
                if (onResizeEnd !is null)
                    onResizeEnd(resizeHandle);
                logLine("UiWindow resize end: ", title, " [", resizeHandle, "]");
                resizeTracking = false;
                resizeHandle = UiResizeHandle.none;
                return true;
            }
        }

        if (event.kind == UiPointerEventKind.buttonDown && event.button == 1)
        {
            const handle = hitResizeHandle(event.x, event.y);
            if (handle != UiResizeHandle.none)
            {
                logLine("UiWindow resize hit: ", title, " [", handle, "] at ", event.x, ", ", event.y);
                resizeHandle = handle;
                resizeTracking = true;
                dragTracking = false;
                if (onResizeStart !is null)
                    onResizeStart(handle);
                return true;
            }

            if (closeButton !is null)
            {
                auto closeEvent = event;
                closeEvent.x -= x;
                closeEvent.y -= y;
                if (closeButton.dispatchPointerEvent(closeEvent))
                {
                    logLine("UiWindow close hit: ", title, " at ", event.x, ", ", event.y);
                    return true;
                }
            }

            if (headerExtras.children.length > 0)
            {
                auto headerEvent = event;
                headerEvent.x -= x;
                headerEvent.y -= y;
                if (headerExtras.dispatchPointerEvent(headerEvent))
                    return true;
            }

            if (dragable && isInDragHeader(event.x, event.y))
            {
                logLine("UiWindow drag start: ", title, " at ", event.x, ", ", event.y);
                if (onHeaderDragStart !is null)
                    onHeaderDragStart(event.x, event.y);
                dragTracking = true;
                resizeTracking = false;
                resizeHandle = UiResizeHandle.none;
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

        return handlePointerEvent(event);
    }

protected:
    /** Draws the chrome and the title badge before the body children are rendered. */
    override void renderSelf(ref UiRenderContext context)
    {
        updateChromeLayout();

        const headerFill = headerColor;
        const bodyFill = bodyColor;

        const gripInset = sizeable ? 18.0f : 0.0f;
        float headerRightInset = gripInset;

        if (headerExtras.children.length > 0)
            headerRightInset += headerExtrasWidth + headerExtras.spacing + 12.0f;

        if (closeButton !is null)
            headerRightInset += closeButton.width + 8.0f;

        appendWindowFrame(context, 0.0f, 0.0f, width, height, headerHeight, bodyFill, headerFill, context.depthBase, gripInset, headerRightInset);

        if (sizeable)
        {
            float[4] gripFill = [0.18f, 0.24f, 0.36f, 0.92f];
            float[4] gripBorder = [0.32f, 0.68f, 0.98f, 0.98f];
            appendButtonFrame(context, 0.0f, 0.0f, 16.0f, 16.0f, gripFill, gripBorder, context.depthBase - 0.0005f);
            appendButtonFrame(context, width - 16.0f, 0.0f, width, 16.0f, gripFill, gripBorder, context.depthBase - 0.0005f);
            appendButtonFrame(context, 0.0f, height - 16.0f, 16.0f, height, gripFill, gripBorder, context.depthBase - 0.0005f);
            appendButtonFrame(context, width - 16.0f, height - 16.0f, width, height, gripFill, gripBorder, context.depthBase - 0.0005f);
        }

        const titleX = sizeable ? 20.0f : 10.0f;
        appendTextLine(context, UiTextStyle.medium, title, titleX, 2.0f, titleColor, context.depthBase - 0.001f);

        if (headerExtras.children.length > 0)
        {
            headerExtras.render(context);
        }

        if (closeButton !is null)
        {
            closeButton.render(context);
        }

        appendWindowBorder(context, 0.0f, 0.0f, width, height, context.depthBase - 0.003f);
    }

    override float[4] debugBoundsColor() const
    {
        return cast(float[4])windowDebugBoundsColor;
    }

private:
    /** Positions the header controls so they stay clear of the resize grip. */
    void updateChromeLayout()
    {
        const closeWidth = closeButton !is null ? closeButton.width : 0.0f;
        const closeGap = closeButton !is null ? 4.0f : 0.0f;
        const gripReserve = sizeable ? 18.0f : 0.0f;
        const contentMargin = 3.0f;
        const chromeTopInset = 7.0f;

        headerExtras.width = headerExtrasWidth;
        headerExtras.height = headerExtrasHeight;
        headerExtras.x = max(10.0f, width - gripReserve - closeWidth - closeGap - headerExtrasWidth - 12.0f);
        headerExtras.y = chromeTopInset + 1.0f;

        contentRoot.x = contentMargin;
        contentRoot.y = headerHeight + contentMargin;
        contentRoot.width = max(width - contentMargin * 2.0f, 0.0f);
        contentRoot.height = max(height - headerHeight - contentMargin * 2.0f, 0.0f);

        if (closeButton !is null)
        {
            closeButton.x = width - gripReserve - closeWidth - 3.0f;
            closeButton.y = max(0.0f, (headerHeight - closeButton.height) * 0.5f);
        }
    }

    /** Recomputes the cached size of the header widgets. */
    void refreshHeaderMetrics()
    {
        float totalWidth = 0.0f;
        float tallest = 0.0f;

        foreach (index, child; headerExtras.children)
        {
            totalWidth += child.width;
            if (index > 0)
                totalWidth += headerExtras.spacing;
            if (child.height > tallest)
                tallest = child.height;
        }

        headerExtrasWidth = totalWidth;
        headerExtrasHeight = tallest;
    }

    /** Handles activation of the built-in close button. */
    void handleCloseButton()
    {
        if (onClose !is null)
            onClose();
        else
            visible = false;
    }

    /** Returns whether the pointer lies in the active header band. */
    bool isInDragHeader(float localX, float localY) const
    {
        if (localX < x || localX >= x + width || localY < y || localY >= y + headerHeight)
            return false;

        if (sizeable)
        {
            if (localX < x + 16.0f && localY < y + 16.0f)
                return false;

            if (localX >= x + width - 16.0f && localY < y + 16.0f)
                return false;
        }

        if (closeButton !is null)
        {
            if (localX >= x + closeButton.x && localX < x + closeButton.x + closeButton.width &&
                localY >= y + closeButton.y && localY < y + closeButton.y + closeButton.height)
            {
                return false;
            }
        }

        if (headerExtras.children.length > 0)
        {
            if (localX >= x + headerExtras.x && localX < x + headerExtras.x + headerExtras.width &&
                localY >= y + headerExtras.y && localY < y + headerExtras.y + headerExtras.height)
            {
                return false;
            }
        }

        return true;
    }

    /** Returns the resize corner hit by the pointer, if any. */
    UiResizeHandle hitResizeHandle(float localX, float localY) const
    {
        if (!sizeable)
            return UiResizeHandle.none;

        if (localX >= x && localX < x + 16.0f && localY >= y && localY < y + 16.0f)
            return UiResizeHandle.topLeft;
        if (localX >= x + width - 16.0f && localX < x + width && localY >= y && localY < y + 16.0f)
            return UiResizeHandle.topRight;
        if (localX >= x && localX < x + 16.0f && localY >= y + height - 16.0f && localY < y + height)
            return UiResizeHandle.bottomLeft;
        if (localX >= x + width - 16.0f && localX < x + width && localY >= y + height - 16.0f && localY < y + height)
            return UiResizeHandle.bottomRight;

        return UiResizeHandle.none;
    }

    /** Tints a color tuple by a small amount without changing the alpha channel. */
    static float[4] tintColor(float[4] color, float amount)
    {
        return [
            color[0] + (1.0f - color[0]) * amount,
            color[1] + (1.0f - color[1]) * amount,
            color[2] + (1.0f - color[2]) * amount,
            color[3],
        ];
    }
}
