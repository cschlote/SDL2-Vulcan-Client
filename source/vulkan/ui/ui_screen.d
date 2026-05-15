/** Screen-level owner for retained UI windows.
 *
 * UiScreen represents the drawable content area of the SDL window. It owns and
 * orders UiWindow objects, routes pointer input to visible windows, and keeps
 * common window interactions such as dragging, resizing, layout, and viewport
 * clamping out of application-level UI construction code.
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.ui.ui_screen;

import std.algorithm : max;

import vulkan.font.font_legacy : FontAtlas;
import vulkan.ui.ui_event : UiPointerEvent, UiResizeHandle;
import vulkan.ui.ui_layout_context : UiLayoutContext;
import vulkan.ui.ui_window : UiWindow;
import vulkan.ui.ui_widget : UiWidget;

class UiScreen
{
    private float viewportWidth_;
    private float viewportHeight_;
    private const(FontAtlas)[] fontAtlases_;
    private UiLayoutContext layoutContext_;
    private UiWindow[] windows_;

    private UiWindow activeDragWindow;
    private UiWindow activeResizeWindow;
    private float dragOffsetX;
    private float dragOffsetY;
    private float resizeStartLeft;
    private float resizeStartTop;
    private float resizeStartWidth;
    private float resizeStartHeight;
    private UiResizeHandle resizeStartHandle;

    void initialize(const(FontAtlas)[] liveFonts)
    {
        fontAtlases_ = liveFonts;
        windows_ = [];
        activeDragWindow = null;
        activeResizeWindow = null;
        resizeStartHandle = UiResizeHandle.none;
        onInitialize();
        ensureWindowLayout();
    }

    void syncViewport(float extentWidth, float extentHeight)
    {
        viewportWidth_ = extentWidth;
        viewportHeight_ = extentHeight;
        ensureWindowLayout();
    }

    bool dispatchPointerEvent(ref UiPointerEvent event)
    {
        if (activeResizeWindow !is null && activeResizeWindow.visible)
            return activeResizeWindow.dispatchPointerEvent(event);

        if (activeDragWindow !is null && activeDragWindow.visible)
            return activeDragWindow.dispatchPointerEvent(event);

        foreach_reverse (window; windowsInFrontToBack())
        {
            if (!window.visible)
                continue;

            if (window.dispatchPointerEvent(event))
                return true;
        }

        return false;
    }

    bool containsPointer(float x, float y) const
    {
        foreach_reverse (window; windowsInFrontToBack())
        {
            if (!window.visible)
                continue;

            if (x >= window.x && x < window.x + window.width && y >= window.y && y < window.y + window.height)
                return true;
        }

        return false;
    }

    UiWindow[] windowsInFrontToBack()
    {
        return windows_;
    }

    const(UiWindow)[] windowsInFrontToBack() const
    {
        return windows_;
    }

    void ensureWindowLayout()
    {
        if (viewportWidth_ <= 0.0f || viewportHeight_ <= 0.0f)
            return;

        layoutWindows();
        anchorWindows();
        clampWindowsToViewport();
    }

protected:
    void onInitialize()
    {
    }

    void anchorWindows()
    {
    }

    @property float viewportWidth() const
    {
        return viewportWidth_;
    }

    @property float viewportHeight() const
    {
        return viewportHeight_;
    }

    @property const(FontAtlas)[] fontAtlases() const
    {
        return fontAtlases_;
    }

    @property ref UiLayoutContext layoutContext()
    {
        return layoutContext_;
    }

    void addWindow(UiWindow window)
    {
        if (window is null)
            return;

        windows_ ~= window;
    }

    void removeWindow(UiWindow window)
    {
        if (window is null)
            return;

        if (isInteractingWith(window))
            endWindowInteraction();

        for (size_t index = 0; index < windows_.length; ++index)
        {
            if (windows_[index] is window)
            {
                windows_ = windows_[0 .. index] ~ windows_[index + 1 .. $];
                break;
            }
        }
    }

    void registerWindowInteractionHandlers(UiWindow window)
    {
        if (window is null)
            return;

        window.onHeaderDragStart = (cursorX, cursorY) { beginWindowDrag(window, cursorX, cursorY); };
        window.onHeaderDragMove = (cursorX, cursorY) { updateWindowDrag(cursorX, cursorY); };
        window.onHeaderDragEnd = () { endWindowInteraction(); };
        window.onResizeStart = (handle) { beginWindowResize(window, handle); };
        window.onResizeMove = (handle, cursorX, cursorY) { updateWindowResize(cursorX, cursorY); };
        window.onResizeEnd = (handle) { endWindowInteraction(); };
    }

    void toggleWindow(UiWindow window)
    {
        if (window is null)
            return;

        window.visible = !window.visible;

        if (!window.visible && isInteractingWith(window))
            endWindowInteraction();

        ensureWindowLayout();
    }

    void endWindowInteraction()
    {
        activeDragWindow = null;
        activeResizeWindow = null;
        resizeStartHandle = UiResizeHandle.none;
    }

    bool isInteractingWith(UiWindow window) const
    {
        return window !is null && (activeDragWindow is window || activeResizeWindow is window);
    }

    static float clampFloat(float value, float minimum, float maximum)
    {
        return value < minimum ? minimum : (value > maximum ? maximum : value);
    }

    UiLayoutContext buildLayoutContext(const(FontAtlas)[] liveFonts) const
    {
        UiLayoutContext context;
        foreach (index; 0 .. context.fonts.length)
            context.fonts[index] = index < liveFonts.length ? &liveFonts[index] : null;
        return context;
    }

    void autoSizeWindow(UiWindow window, UiWidget content, float paddingLeft, float paddingTop, float paddingRight, float paddingBottom, float minimumWidth, float minimumHeight)
    {
        if (window is null || content is null || fontAtlases_.length == 0)
            return;

        auto sizeContext = buildLayoutContext(fontAtlases_);
        const contentSize = content.measure(sizeContext);
        const desiredWidth = contentSize.width + paddingLeft + paddingRight;
        const desiredHeight = contentSize.height + paddingTop + paddingBottom + window.headerHeight;
        const effectiveMinimumWidth = max(minimumWidth, window.minimumWidth);
        const effectiveMinimumHeight = max(minimumHeight, window.minimumHeight);
        const minimumWindowWidth = max(effectiveMinimumWidth, desiredWidth);
        const minimumWindowHeight = max(effectiveMinimumHeight, desiredHeight);

        window.minimumWidth = minimumWindowWidth;
        window.minimumHeight = minimumWindowHeight;

        if (window.width < minimumWindowWidth)
            window.width = minimumWindowWidth;
        if (window.height < minimumWindowHeight)
            window.height = minimumWindowHeight;
    }

    void clampWindowToViewport(UiWindow window)
    {
        if (window is null)
            return;

        const maximumLeft = viewportWidth_ > window.width ? viewportWidth_ - window.width : 0.0f;
        const maximumTop = viewportHeight_ > window.height ? viewportHeight_ - window.height : 0.0f;
        window.x = clampFloat(window.x, 0.0f, maximumLeft);
        window.y = clampFloat(window.y, 0.0f, maximumTop);
    }

private:
    void beginWindowDrag(UiWindow window, float cursorX, float cursorY)
    {
        activeDragWindow = window;
        activeResizeWindow = null;
        dragOffsetX = cursorX - window.x;
        dragOffsetY = cursorY - window.y;
    }

    void updateWindowDrag(float cursorX, float cursorY)
    {
        if (activeDragWindow is null)
            return;

        const newLeft = cursorX - dragOffsetX;
        const newTop = cursorY - dragOffsetY;
        const maximumLeft = viewportWidth_ > activeDragWindow.width ? viewportWidth_ - activeDragWindow.width : 0.0f;
        const maximumTop = viewportHeight_ > activeDragWindow.height ? viewportHeight_ - activeDragWindow.height : 0.0f;
        activeDragWindow.x = clampFloat(newLeft, 0.0f, maximumLeft);
        activeDragWindow.y = clampFloat(newTop, 0.0f, maximumTop);
    }

    void beginWindowResize(UiWindow window, UiResizeHandle handle)
    {
        activeResizeWindow = window;
        activeDragWindow = null;
        resizeStartHandle = handle;
        resizeStartLeft = window.x;
        resizeStartTop = window.y;
        resizeStartWidth = window.width;
        resizeStartHeight = window.height;
    }

    void updateWindowResize(float cursorX, float cursorY)
    {
        if (activeResizeWindow is null)
            return;

        const minimumWidth = activeResizeWindow.minimumWidth > 0.0f ? activeResizeWindow.minimumWidth : 240.0f;
        const minimumHeight = activeResizeWindow.minimumHeight > 0.0f ? activeResizeWindow.minimumHeight : 160.0f;
        const startRight = resizeStartLeft + resizeStartWidth;
        const startBottom = resizeStartTop + resizeStartHeight;

        final switch (resizeStartHandle)
        {
            case UiResizeHandle.topLeft:
            {
                const newLeft = clampFloat(cursorX, 0.0f, startRight - minimumWidth);
                const newTop = clampFloat(cursorY, 0.0f, startBottom - minimumHeight);
                activeResizeWindow.x = newLeft;
                activeResizeWindow.y = newTop;
                activeResizeWindow.width = startRight - newLeft;
                activeResizeWindow.height = startBottom - newTop;
                break;
            }
            case UiResizeHandle.topRight:
            {
                const availableRight = viewportWidth_ > resizeStartLeft ? viewportWidth_ - resizeStartLeft : minimumWidth;
                const newTop = clampFloat(cursorY, 0.0f, startBottom - minimumHeight);
                activeResizeWindow.y = newTop;
                activeResizeWindow.width = clampFloat(cursorX - resizeStartLeft, minimumWidth, availableRight);
                activeResizeWindow.height = startBottom - newTop;
                break;
            }
            case UiResizeHandle.bottomLeft:
            {
                const availableBottom = viewportHeight_ > resizeStartTop ? viewportHeight_ - resizeStartTop : minimumHeight;
                const newLeft = clampFloat(cursorX, 0.0f, startRight - minimumWidth);
                activeResizeWindow.x = newLeft;
                activeResizeWindow.width = startRight - newLeft;
                activeResizeWindow.height = clampFloat(cursorY - resizeStartTop, minimumHeight, availableBottom);
                break;
            }
            case UiResizeHandle.bottomRight:
            {
                const availableWidth = viewportWidth_ > resizeStartLeft ? viewportWidth_ - resizeStartLeft : minimumWidth;
                const availableHeight = viewportHeight_ > resizeStartTop ? viewportHeight_ - resizeStartTop : minimumHeight;
                activeResizeWindow.width = clampFloat(cursorX - resizeStartLeft, minimumWidth, availableWidth);
                activeResizeWindow.height = clampFloat(cursorY - resizeStartTop, minimumHeight, availableHeight);
                break;
            }
            case UiResizeHandle.none:
                break;
        }

        clampWindowToViewport(activeResizeWindow);
    }

    void layoutWindows()
    {
        if (fontAtlases_.length == 0)
            return;

        layoutContext_ = buildLayoutContext(fontAtlases_);
        foreach (window; windows_)
            window.layoutWindow(layoutContext_);
    }

    void clampWindowsToViewport()
    {
        foreach (window; windows_)
            clampWindowToViewport(window);
    }
}
