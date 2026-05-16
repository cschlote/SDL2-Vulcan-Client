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
import vulkan.ui.ui_context : UiRenderContext;
import vulkan.ui.ui_cursor : UiCursorKind, cursorForResizeHandle;
import vulkan.ui.ui_event : UiKeyCode, UiKeyEvent, UiKeyEventKind, UiKeyModifier, UiPointerEvent, UiPointerEventKind, UiResizeHandle, UiTextInputEvent;
import vulkan.ui.ui_geometry : UiOverlayGeometry, UiWindowDrawRange;
import vulkan.ui.ui_layout_context : UiLayoutContext;
import vulkan.ui.ui_window : UiWindow;
import vulkan.ui.ui_widget : UiWidget;

version (unittest)
    import vulkan.ui.ui_controls : UiTextField;

/** Screen-level coordinator for retained UI windows. */
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
    private UiWidget focusedWidget;
    private UiWindow activePopupWindow;

    /** Initializes the screen with the font atlases used for layout. */
    void initialize(const(FontAtlas)[] liveFonts)
    {
        viewportWidth_ = 0.0f;
        viewportHeight_ = 0.0f;
        fontAtlases_ = liveFonts;
        windows_ = [];
        activeDragWindow = null;
        activeResizeWindow = null;
        activePopupWindow = null;
        resizeStartHandle = UiResizeHandle.none;
        setFocusedWidget(null);
        onInitialize();
        ensureWindowLayout();
    }

    /** Updates the screen viewport in native window pixels and relayouts windows. */
    void syncViewport(float extentWidth, float extentHeight)
    {
        viewportWidth_ = extentWidth;
        viewportHeight_ = extentHeight;
        ensureWindowLayout();
    }

    /** Routes a pointer event to active interactions or the front-most window. */
    bool dispatchPointerEvent(ref UiPointerEvent event)
    {
        event.screenX = event.x;
        event.screenY = event.y;

        if (event.kind == UiPointerEventKind.buttonDown && activePopupWindow !is null)
        {
            if (!activePopupWindow.visible)
                activePopupWindow = null;
            else if (!windowContainsPointer(activePopupWindow, event.x, event.y))
            {
                dismissActivePopup();
                if (event.button == 1)
                    setFocusedWidget(null);
                return true;
            }
        }

        if (event.kind == UiPointerEventKind.buttonDown && event.button == 1)
            setFocusedWidget(focusTargetAt(event.x, event.y));

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

    /** Routes a keyboard event to the focused widget. */
    bool dispatchKeyEvent(ref UiKeyEvent event)
    {
        if (event.kind == UiKeyEventKind.keyDown && event.key == UiKeyCode.tab)
        {
            focusNextWidget((event.modifiers & cast(uint)UiKeyModifier.shift) != 0);
            return true;
        }

        if (event.kind == UiKeyEventKind.keyDown && event.key == UiKeyCode.escape && hasActivePopup())
        {
            dismissActivePopup();
            return true;
        }

        if (event.kind == UiKeyEventKind.keyDown && event.key == UiKeyCode.escape && focusedWidget !is null)
        {
            setFocusedWidget(null);
            return true;
        }

        if (focusedWidget is null)
            return false;

        return focusedWidget.dispatchKeyEvent(event);
    }

    /** Routes UTF-8 text input to the focused widget. */
    bool dispatchTextInputEvent(ref UiTextInputEvent event)
    {
        if (focusedWidget is null || event.text.length == 0)
            return false;

        return focusedWidget.dispatchTextInputEvent(event);
    }

    /** Returns true while a widget owns keyboard focus. */
    bool hasKeyboardFocus() const
    {
        return focusedWidget !is null;
    }

    /** Returns the currently focused widget, or null when no widget owns focus. */
    UiWidget currentFocusedWidget()
    {
        return focusedWidget;
    }

    /** Returns true when the point is inside any visible window. */
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

    /** Returns the cursor intent for the front-most visible UI region. */
    UiCursorKind cursorAt(float x, float y)
    {
        if (activeResizeWindow !is null && activeResizeWindow.visible)
            return cursorForResizeHandle(resizeStartHandle);

        if (activeDragWindow !is null && activeDragWindow.visible)
            return UiCursorKind.move;

        foreach_reverse (window; windowsInFrontToBack())
        {
            if (!window.visible)
                continue;

            if (x >= window.x && x < window.x + window.width && y >= window.y && y < window.y + window.height)
                return window.cursorAt(x, y);
        }

        return UiCursorKind.default_;
    }

    /** Returns the windows in draw order from back to front. */
    UiWindow[] windowsInFrontToBack()
    {
        return windows_;
    }

    /** Returns the windows in draw order from back to front. */
    const(UiWindow)[] windowsInFrontToBack() const
    {
        return windows_;
    }

    /** Recomputes layout and keeps windows inside the viewport. */
    void ensureWindowLayout()
    {
        if (viewportWidth_ <= 0.0f || viewportHeight_ <= 0.0f)
            return;

        layoutWindows();
        anchorWindows();
        clampWindowsToViewport();
        keepActivePopupFront();
    }

    /** Shows a transient popup window near an anchor rectangle in screen coordinates. */
    void showPopupWindow(UiWindow popup, float anchorX, float anchorY, float anchorWidth, float anchorHeight)
    {
        if (popup is null)
            return;

        if (activePopupWindow !is null && activePopupWindow !is popup)
            activePopupWindow.visible = false;

        if (windowIndex(popup) < 0)
            addWindow(popup);

        popup.visible = true;
        activePopupWindow = popup;
        placePopupNearAnchor(popup, anchorX, anchorY, anchorWidth, anchorHeight);
        bringWindowToFront(popup);
    }

    /** Hides the currently active transient popup, if any. */
    void dismissActivePopup()
    {
        if (activePopupWindow is null)
            return;

        activePopupWindow.visible = false;
        activePopupWindow = null;
    }

    /** Returns true while a visible transient popup is active. */
    bool hasActivePopup() const
    {
        return activePopupWindow !is null && activePopupWindow.visible;
    }

    /** Builds renderer-facing overlay geometry for all visible windows.
     *
     * Params:
     *   debugWidgetBounds = Draws per-widget debug outlines when enabled.
     *   windowDepth = Base depth used by top-level window rendering.
     *
     * Returns:
     *   UI panel, text-layer, and draw-range geometry in retained window order.
     */
    UiOverlayGeometry buildOverlayGeometry(bool debugWidgetBounds = false, float windowDepth = 0.10f)
    {
        UiOverlayGeometry geometry;
        geometry.panels = [];
        foreach (layerIndex; 0 .. geometry.textLayers.length)
            geometry.textLayers[layerIndex] = [];

        auto context = buildRenderContext(geometry, debugWidgetBounds, windowDepth);
        UiWindowDrawRange[] drawRanges;

        foreach (window; windowsInFrontToBack())
        {
            if (!window.visible)
                continue;

            UiWindowDrawRange range;
            range.panelsStart = cast(uint)geometry.panels.length;
            foreach (layerIndex; 0 .. geometry.textLayers.length)
                range.textStarts[layerIndex] = cast(uint)geometry.textLayers[layerIndex].length;

            context.depthBase = windowDepth;
            window.render(context);

            range.panelsCount = cast(uint)(geometry.panels.length - range.panelsStart);
            foreach (layerIndex; 0 .. geometry.textLayers.length)
                range.textCounts[layerIndex] = cast(uint)(geometry.textLayers[layerIndex].length - range.textStarts[layerIndex]);

            drawRanges ~= range;
        }

        geometry.windows = drawRanges;
        return geometry;
    }

protected:
    /** Hook for subclasses to build and register their windows. */
    void onInitialize()
    {
    }

    /** Hook for subclasses to place initial windows after layout. */
    void anchorWindows()
    {
    }

    /** Current viewport width in native window pixels. */
    @property float viewportWidth() const
    {
        return viewportWidth_;
    }

    /** Current viewport height in native window pixels. */
    @property float viewportHeight() const
    {
        return viewportHeight_;
    }

    /** Font atlases used by the screen layout context. */
    @property const(FontAtlas)[] fontAtlases() const
    {
        return fontAtlases_;
    }

    /** Last layout context built by `ensureWindowLayout`. */
    @property ref UiLayoutContext layoutContext()
    {
        return layoutContext_;
    }

    /** Registers a window at the front of the draw order. */
    void addWindow(UiWindow window)
    {
        if (window is null)
            return;

        windows_ ~= window;
    }

    /** Removes a registered window and cancels active interactions for it. */
    void removeWindow(UiWindow window)
    {
        if (window is null)
            return;

        if (isInteractingWith(window))
            endWindowInteraction();

        if (activePopupWindow is window)
            activePopupWindow = null;

        if (focusedWidget !is null && windowOwnsWidget(window, focusedWidget))
            setFocusedWidget(null);

        for (size_t index = 0; index < windows_.length; ++index)
        {
            if (windows_[index] is window)
            {
                windows_ = windows_[0 .. index] ~ windows_[index + 1 .. $];
                break;
            }
        }
    }

    /** Connects a window's generic drag, resize, and stack callbacks. */
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
        window.onHeaderMiddleClick = () { toggleWindowStackPosition(window); };
    }

    /** Toggles visibility and places a shown window in usable screen space. */
    void toggleWindow(UiWindow window)
    {
        if (window is null)
            return;

        window.visible = !window.visible;

        if (!window.visible && isInteractingWith(window))
            endWindowInteraction();
        if (!window.visible && activePopupWindow is window)
            activePopupWindow = null;
        else if (window.visible)
            bringWindowToFront(window);

        ensureWindowLayout();
        if (window.visible)
            placeWindowWithoutOverlap(window);
    }

    /** Moves a registered window to the front of the draw order. */
    void bringWindowToFront(UiWindow window)
    {
        if (!moveWindowToFront(window))
            return;

        if (activePopupWindow !is null && activePopupWindow !is window && activePopupWindow.visible)
            moveWindowToFront(activePopupWindow);
    }

    /** Moves a registered window to the back of the draw order. */
    void sendWindowToBack(UiWindow window)
    {
        const index = windowIndex(window);
        if (index <= 0)
            return;

        windows_ = window ~ windows_[0 .. cast(size_t)index] ~ windows_[cast(size_t)index + 1 .. $];
    }

    /** Brings a window forward, or sends it back when it is already front-most. */
    void toggleWindowStackPosition(UiWindow window)
    {
        if (window is null)
            return;

        if (isFrontWindow(window))
            sendWindowToBack(window);
        else
            bringWindowToFront(window);
    }

    /** Returns true when `window` is the front-most registered window. */
    bool isFrontWindow(UiWindow window) const
    {
        return window !is null && windows_.length > 0 && windows_[$ - 1] is window;
    }

    /** Attempts to move `window` to the first free non-overlapping viewport slot. */
    void placeWindowWithoutOverlap(UiWindow window, float inset = 10.0f, float step = 24.0f)
    {
        if (window is null || viewportWidth_ <= 0.0f || viewportHeight_ <= 0.0f)
            return;

        clampWindowToViewport(window);
        if (!overlapsVisibleWindow(window, window.x, window.y))
            return;

        const maximumLeft = viewportWidth_ > window.width ? viewportWidth_ - window.width : 0.0f;
        const maximumTop = viewportHeight_ > window.height ? viewportHeight_ - window.height : 0.0f;
        const startX = clampFloat(inset, 0.0f, maximumLeft);
        const startY = clampFloat(inset, 0.0f, maximumTop);
        const effectiveStep = step > 0.0f ? step : 24.0f;

        for (float y = startY; y <= maximumTop; y += effectiveStep)
        {
            for (float x = startX; x <= maximumLeft; x += effectiveStep)
            {
                if (!overlapsVisibleWindow(window, x, y))
                {
                    window.x = x;
                    window.y = y;
                    return;
                }
            }
        }

        clampWindowToViewport(window);
    }

    /** Cancels active window dragging or resizing. */
    void endWindowInteraction()
    {
        activeDragWindow = null;
        activeResizeWindow = null;
        resizeStartHandle = UiResizeHandle.none;
    }

    /** Sets the current keyboard focus owner. */
    void setFocusedWidget(UiWidget widget)
    {
        if (focusedWidget is widget)
            return;

        if (focusedWidget !is null)
            focusedWidget.setFocused(false);

        focusedWidget = widget;

        if (focusedWidget !is null)
            focusedWidget.setFocused(true);
    }

    /** Returns true when the window is currently dragged or resized. */
    bool isInteractingWith(UiWindow window) const
    {
        return window !is null && (activeDragWindow is window || activeResizeWindow is window);
    }

    /** Clamps a scalar value into a closed range. */
    static float clampFloat(float value, float minimum, float maximum)
    {
        return value < minimum ? minimum : (value > maximum ? maximum : value);
    }

    /** Builds a layout context from the provided font atlases. */
    UiLayoutContext buildLayoutContext(const(FontAtlas)[] liveFonts) const
    {
        UiLayoutContext context;
        foreach (index; 0 .. context.fonts.length)
            context.fonts[index] = index < liveFonts.length ? &liveFonts[index] : null;
        return context;
    }

    /** Builds a render context targeting the provided overlay geometry.
     *
     * Params:
     *   geometry = Overlay geometry that receives emitted panel and text vertices.
     *   debugWidgetBounds = Draws per-widget debug outlines when enabled.
     *   windowDepth = Initial base depth used for window rendering.
     *
     * Returns:
     *   Render context bound to this screen's viewport and font atlases.
     */
    UiRenderContext buildRenderContext(ref UiOverlayGeometry geometry, bool debugWidgetBounds, float windowDepth) const
    {
        UiRenderContext context = UiRenderContext.init;
        context.extentWidth = viewportWidth_;
        context.extentHeight = viewportHeight_;
        context.originX = 0.0f;
        context.originY = 0.0f;
        context.depthBase = windowDepth;
        context.debugWidgetBounds = debugWidgetBounds;
        foreach (index; 0 .. context.fonts.length)
            context.fonts[index] = index < fontAtlases_.length ? &fontAtlases_[index] : null;
        context.panels = &geometry.panels;
        foreach (index; 0 .. context.textLayers.length)
            context.textLayers[index] = &geometry.textLayers[index];
        return context;
    }

    /** Measures content and applies effective minimum window size. */
    void autoSizeWindow(UiWindow window, UiWidget content, float paddingLeft, float paddingTop, float paddingRight, float paddingBottom, float minimumWidth, float minimumHeight)
    {
        if (window is null || content is null || fontAtlases_.length == 0)
            return;

        auto sizeContext = buildLayoutContext(fontAtlases_);
        const contentSize = content.measure(sizeContext);
        const desiredWidth = contentSize.width + paddingLeft + paddingRight;
        const desiredHeight = contentSize.height + paddingTop + paddingBottom + window.verticalChromeExtent();
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

    /** Keeps a window fully inside the current viewport when possible. */
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
    void focusNextWidget(bool reverse)
    {
        auto widgets = focusableWidgetsInTraversalOrder();
        if (widgets.length == 0)
        {
            setFocusedWidget(null);
            return;
        }

        ptrdiff_t currentIndex = -1;
        foreach (index, widget; widgets)
        {
            if (widget is focusedWidget)
            {
                currentIndex = cast(ptrdiff_t)index;
                break;
            }
        }

        size_t nextIndex;
        if (currentIndex < 0)
            nextIndex = reverse ? widgets.length - 1 : 0;
        else if (reverse)
            nextIndex = currentIndex == 0 ? widgets.length - 1 : cast(size_t)(currentIndex - 1);
        else
            nextIndex = (cast(size_t)currentIndex + 1) % widgets.length;

        setFocusedWidget(widgets[nextIndex]);
    }

    UiWidget[] focusableWidgetsInTraversalOrder()
    {
        UiWidget[] widgets;
        foreach_reverse (window; windowsInFrontToBack())
        {
            if (!window.visible)
                continue;

            collectFocusableWidgets(window, widgets);
        }
        return widgets;
    }

    static void collectFocusableWidgets(UiWidget root, ref UiWidget[] widgets)
    {
        if (root is null || !root.visible)
            return;

        if (root.focusable)
            widgets ~= root;

        foreach (child; root.children)
            collectFocusableWidgets(child, widgets);
    }

    static bool windowContainsPointer(UiWindow window, float x, float y)
    {
        return window !is null && x >= window.x && x < window.x + window.width && y >= window.y && y < window.y + window.height;
    }

    void placePopupNearAnchor(UiWindow popup, float anchorX, float anchorY, float anchorWidth, float anchorHeight)
    {
        const anchorRight = anchorX + anchorWidth;
        const anchorBottom = anchorY + anchorHeight;
        popup.x = anchorX;
        popup.y = anchorBottom;

        if (viewportWidth_ <= 0.0f || viewportHeight_ <= 0.0f)
            return;

        if (popup.x + popup.width > viewportWidth_)
        {
            const anchoredLeft = anchorRight - popup.width;
            popup.x = anchoredLeft >= 0.0f ? anchoredLeft : (viewportWidth_ > popup.width ? viewportWidth_ - popup.width : 0.0f);
        }
        if (popup.x < 0.0f)
            popup.x = 0.0f;

        if (popup.y + popup.height > viewportHeight_)
        {
            const aboveTop = anchorY - popup.height;
            popup.y = aboveTop >= 0.0f ? aboveTop : (viewportHeight_ > popup.height ? viewportHeight_ - popup.height : 0.0f);
        }

        if (popup.y < 0.0f)
            popup.y = 0.0f;
    }

    bool moveWindowToFront(UiWindow window)
    {
        const index = windowIndex(window);
        if (index < 0 || cast(size_t)index + 1 == windows_.length)
            return false;

        windows_ = windows_[0 .. cast(size_t)index] ~ windows_[cast(size_t)index + 1 .. $] ~ window;
        return true;
    }

    void keepActivePopupFront()
    {
        if (activePopupWindow !is null && activePopupWindow.visible)
            moveWindowToFront(activePopupWindow);
    }

    UiWidget focusTargetAt(float x, float y)
    {
        foreach_reverse (window; windowsInFrontToBack())
        {
            if (!window.visible)
                continue;

            auto target = window.focusTargetAt(x, y);
            if (target !is null)
                return target;
        }

        return null;
    }

    static bool windowOwnsWidget(UiWidget root, UiWidget needle)
    {
        if (root is null || needle is null)
            return false;

        if (root is needle)
            return true;

        foreach (child; root.children)
        {
            if (windowOwnsWidget(child, needle))
                return true;
        }

        return false;
    }

    ptrdiff_t windowIndex(UiWindow window) const
    {
        foreach (index, candidate; windows_)
        {
            if (candidate is window)
                return cast(ptrdiff_t)index;
        }

        return -1;
    }

    bool overlapsVisibleWindow(UiWindow window, float candidateX, float candidateY) const
    {
        foreach (other; windows_)
        {
            if (other is window || other is null || !other.visible)
                continue;

            if (rectsOverlap(candidateX, candidateY, window.width, window.height, other.x, other.y, other.width, other.height))
                return true;
        }

        return false;
    }

    static bool rectsOverlap(float leftA, float topA, float widthA, float heightA, float leftB, float topB, float widthB, float heightB)
    {
        return leftA < leftB + widthB &&
            leftA + widthA > leftB &&
            topA < topB + heightB &&
            topA + heightA > topB;
    }

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
            case UiResizeHandle.top:
            {
                const newTop = clampFloat(cursorY, 0.0f, startBottom - minimumHeight);
                activeResizeWindow.y = newTop;
                activeResizeWindow.height = startBottom - newTop;
                break;
            }
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
            case UiResizeHandle.right:
            {
                const availableRight = viewportWidth_ > resizeStartLeft ? viewportWidth_ - resizeStartLeft : minimumWidth;
                activeResizeWindow.width = clampFloat(cursorX - resizeStartLeft, minimumWidth, availableRight);
                break;
            }
            case UiResizeHandle.bottom:
            {
                const availableBottom = viewportHeight_ > resizeStartTop ? viewportHeight_ - resizeStartTop : minimumHeight;
                activeResizeWindow.height = clampFloat(cursorY - resizeStartTop, minimumHeight, availableBottom);
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
            case UiResizeHandle.left:
            {
                const newLeft = clampFloat(cursorX, 0.0f, startRight - minimumWidth);
                activeResizeWindow.x = newLeft;
                activeResizeWindow.width = startRight - newLeft;
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

@("UiScreen reorders windows without z values")
unittest
{
    auto screen = new UiScreen();
    screen.initialize([]);

    auto first = new UiWindow("first", 0.0f, 0.0f, 40.0f, 40.0f, [0.0f, 0.0f, 0.0f, 1.0f], [0.0f, 0.0f, 0.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f]);
    auto second = new UiWindow("second", 0.0f, 0.0f, 40.0f, 40.0f, [0.0f, 0.0f, 0.0f, 1.0f], [0.0f, 0.0f, 0.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f]);
    screen.addWindow(first);
    screen.addWindow(second);

    assert(screen.isFrontWindow(second));
    screen.bringWindowToFront(first);
    assert(screen.isFrontWindow(first));
    screen.toggleWindowStackPosition(first);
    assert(screen.windowsInFrontToBack()[0] is first);
}

@("UiScreen toggles window stacking from a middle chrome click")
unittest
{
    auto screen = new UiScreen();
    screen.initialize([]);

    auto first = new UiWindow("first", 0.0f, 0.0f, 80.0f, 80.0f, [0.0f, 0.0f, 0.0f, 1.0f], [0.0f, 0.0f, 0.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f], false, false, false);
    auto second = new UiWindow("second", 100.0f, 0.0f, 80.0f, 80.0f, [0.0f, 0.0f, 0.0f, 1.0f], [0.0f, 0.0f, 0.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f], false, false, true);
    screen.registerWindowInteractionHandlers(first);
    screen.registerWindowInteractionHandlers(second);
    screen.addWindow(first);
    screen.addWindow(second);

    UiPointerEvent event;
    event.kind = UiPointerEventKind.buttonDown;
    event.button = 2;
    event.x = 10.0f;
    event.y = 10.0f;

    assert(screen.dispatchPointerEvent(event));
    assert(screen.isFrontWindow(first));

    event.y = 35.0f;
    assert(!screen.dispatchPointerEvent(event));
    assert(screen.isFrontWindow(first));

    event.y = 78.0f;
    assert(screen.dispatchPointerEvent(event));
    assert(screen.windowsInFrontToBack()[0] is first);

    first.stackable = false;
    assert(!screen.dispatchPointerEvent(event));
    assert(screen.windowsInFrontToBack()[0] is first);
}

@("UiScreen builds overlay geometry in retained window order")
unittest
{
    auto screen = new UiScreen();
    screen.initialize([]);
    screen.syncViewport(220.0f, 160.0f);

    auto hidden = new UiWindow("hidden", 10.0f, 10.0f, 70.0f, 60.0f, [0.0f, 0.0f, 0.0f, 1.0f], [0.0f, 0.0f, 0.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f]);
    auto visible = new UiWindow("visible", 90.0f, 10.0f, 70.0f, 60.0f, [0.0f, 0.0f, 0.0f, 1.0f], [0.0f, 0.0f, 0.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f]);
    hidden.visible = false;
    screen.addWindow(hidden);
    screen.addWindow(visible);

    auto geometry = screen.buildOverlayGeometry();
    assert(geometry.windows.length == 1);
    assert(geometry.panels.length > 0);
    assert(geometry.windows[0].panelsStart == 0);
    assert(geometry.windows[0].panelsCount == geometry.panels.length);
}

@("UiScreen reports context-sensitive cursor intent")
unittest
{
    auto screen = new UiScreen();
    screen.initialize([]);
    screen.syncViewport(260.0f, 180.0f);

    auto window = new UiWindow("window", 10.0f, 10.0f, 180.0f, 120.0f, [0.0f, 0.0f, 0.0f, 1.0f], [0.0f, 0.0f, 0.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f], true, false, true);
    auto field = new UiTextField("", "Name", 0.0f, 0.0f, 120.0f, 28.0f);
    window.add(field);
    screen.addWindow(window);

    assert(screen.cursorAt(10.0f, 10.0f) == UiCursorKind.resizeNwse);
    assert(screen.cursorAt(80.0f, 20.0f) == UiCursorKind.move);
    assert(screen.cursorAt(25.0f, 48.0f) == UiCursorKind.text);
    assert(screen.cursorAt(240.0f, 160.0f) == UiCursorKind.default_);
}

@("UiScreen resizes windows from edge grips with non-primary buttons")
unittest
{
    auto screen = new UiScreen();
    screen.initialize([]);
    screen.syncViewport(220.0f, 160.0f);

    auto window = new UiWindow("window", 10.0f, 10.0f, 80.0f, 70.0f, [0.0f, 0.0f, 0.0f, 1.0f], [0.0f, 0.0f, 0.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f], true, false, true);
    window.minimumWidth = 40.0f;
    window.minimumHeight = 40.0f;
    screen.registerWindowInteractionHandlers(window);
    screen.addWindow(window);

    UiPointerEvent event;
    event.kind = UiPointerEventKind.buttonDown;
    event.button = 3;
    event.x = 88.0f;
    event.y = 42.0f;
    assert(screen.dispatchPointerEvent(event));

    event.kind = UiPointerEventKind.move;
    event.x = 110.0f;
    event.y = 42.0f;
    assert(screen.dispatchPointerEvent(event));
    assert(window.width == 100.0f);
    assert(window.height == 70.0f);

    event.kind = UiPointerEventKind.buttonUp;
    event.button = 3;
    assert(screen.dispatchPointerEvent(event));
}

@("UiScreen assigns and clears keyboard focus from pointer input")
unittest
{
    auto screen = new UiScreen();
    screen.initialize([]);

    auto window = new UiWindow("window", 0.0f, 0.0f, 180.0f, 90.0f, [0.0f, 0.0f, 0.0f, 1.0f], [0.0f, 0.0f, 0.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f]);
    auto field = new UiTextField("", "Name", 8.0f, 8.0f, 120.0f, 28.0f);
    window.add(field);
    screen.addWindow(window);

    UiPointerEvent event;
    event.kind = UiPointerEventKind.buttonDown;
    event.button = 1;
    event.x = 14.0f;
    event.y = window.headerHeight + 14.0f;
    assert(screen.dispatchPointerEvent(event));
    assert(field.focused);
    assert(screen.hasKeyboardFocus());

    event.x = 170.0f;
    event.y = 86.0f;
    assert(!screen.dispatchPointerEvent(event));
    assert(!field.focused);
    assert(!screen.hasKeyboardFocus());
}

@("UiScreen traverses focusable widgets with Tab")
unittest
{
    auto screen = new UiScreen();
    screen.initialize([]);

    auto window = new UiWindow("window", 0.0f, 0.0f, 220.0f, 120.0f, [0.0f, 0.0f, 0.0f, 1.0f], [0.0f, 0.0f, 0.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f]);
    auto first = new UiTextField("", "First", 8.0f, 8.0f, 120.0f, 28.0f);
    auto second = new UiTextField("", "Second", 8.0f, 42.0f, 120.0f, 28.0f);
    window.add(first);
    window.add(second);
    screen.addWindow(window);

    UiKeyEvent event;
    event.kind = UiKeyEventKind.keyDown;
    event.key = UiKeyCode.tab;
    assert(screen.dispatchKeyEvent(event));
    assert(screen.currentFocusedWidget() is first);
    assert(first.focused);

    assert(screen.dispatchKeyEvent(event));
    assert(screen.currentFocusedWidget() is second);
    assert(!first.focused);
    assert(second.focused);

    event.modifiers = cast(uint)UiKeyModifier.shift;
    assert(screen.dispatchKeyEvent(event));
    assert(screen.currentFocusedWidget() is first);
}

@("UiScreen can place a window away from existing visible windows")
unittest
{
    auto screen = new UiScreen();
    screen.initialize([]);
    screen.syncViewport(260.0f, 160.0f);

    auto occupied = new UiWindow("occupied", 10.0f, 10.0f, 80.0f, 80.0f, [0.0f, 0.0f, 0.0f, 1.0f], [0.0f, 0.0f, 0.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f]);
    auto target = new UiWindow("target", 10.0f, 10.0f, 60.0f, 60.0f, [0.0f, 0.0f, 0.0f, 1.0f], [0.0f, 0.0f, 0.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f]);
    screen.addWindow(occupied);
    screen.addWindow(target);

    screen.placeWindowWithoutOverlap(target, 10.0f, 24.0f);
    assert(!UiScreen.rectsOverlap(target.x, target.y, target.width, target.height, occupied.x, occupied.y, occupied.width, occupied.height));
}

@("UiScreen shows popups near anchors and keeps them front-most")
unittest
{
    auto screen = new UiScreen();
    screen.initialize([]);
    screen.syncViewport(220.0f, 140.0f);

    auto window = new UiWindow("window", 20.0f, 20.0f, 80.0f, 60.0f, [0.0f, 0.0f, 0.0f, 1.0f], [0.0f, 0.0f, 0.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f]);
    auto popup = new UiWindow("popup", 0.0f, 0.0f, 90.0f, 50.0f, [0.0f, 0.0f, 0.0f, 1.0f], [0.0f, 0.0f, 0.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f]);
    popup.visible = false;
    screen.addWindow(window);

    screen.showPopupWindow(popup, 30.0f, 40.0f, 80.0f, 20.0f);

    assert(screen.hasActivePopup());
    assert(popup.visible);
    assert(popup.x == 30.0f);
    assert(popup.y == 60.0f);
    assert(screen.isFrontWindow(popup));

    screen.bringWindowToFront(window);
    assert(screen.isFrontWindow(popup));
}

@("UiScreen clamps popups to the viewport around anchors")
unittest
{
    auto screen = new UiScreen();
    screen.initialize([]);
    screen.syncViewport(200.0f, 120.0f);

    auto popup = new UiWindow("popup", 0.0f, 0.0f, 80.0f, 50.0f, [0.0f, 0.0f, 0.0f, 1.0f], [0.0f, 0.0f, 0.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f]);
    popup.visible = false;

    screen.showPopupWindow(popup, 170.0f, 100.0f, 20.0f, 18.0f);

    assert(popup.x == 110.0f);
    assert(popup.y == 50.0f);
}

@("UiScreen dismisses active popups on outside click or Escape")
unittest
{
    auto screen = new UiScreen();
    screen.initialize([]);
    screen.syncViewport(220.0f, 140.0f);

    auto popup = new UiWindow("popup", 0.0f, 0.0f, 80.0f, 50.0f, [0.0f, 0.0f, 0.0f, 1.0f], [0.0f, 0.0f, 0.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f]);
    popup.visible = false;

    screen.showPopupWindow(popup, 20.0f, 20.0f, 60.0f, 20.0f);

    UiPointerEvent event;
    event.kind = UiPointerEventKind.buttonDown;
    event.button = 1;
    event.x = 180.0f;
    event.y = 100.0f;
    assert(screen.dispatchPointerEvent(event));
    assert(!popup.visible);
    assert(!screen.hasActivePopup());

    screen.showPopupWindow(popup, 20.0f, 20.0f, 60.0f, 20.0f);

    UiKeyEvent keyEvent;
    keyEvent.kind = UiKeyEventKind.keyDown;
    keyEvent.key = UiKeyCode.escape;
    assert(screen.dispatchKeyEvent(keyEvent));
    assert(!popup.visible);
    assert(!screen.hasActivePopup());
}
