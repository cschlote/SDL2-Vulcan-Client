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
import vulkan.ui.ui_cursor : UiCursorKind, cursorForResizeHandle;
import vulkan.ui.ui_event : UiPointerEvent, UiPointerEventKind, UiResizeHandle;
import vulkan.ui.ui_layout_context : UiLayoutContext;
import vulkan.ui.ui_layout : UiContentBox, UiHBox, UiVBox;
import vulkan.ui.ui_widget : UiWidget;
import vulkan.ui.ui_widget_helpers : appendQuad, appendTextLine, appendTriangle, appendWindowBorder, appendWindowFrame;
import logging : logLine;

private immutable float[4] windowDebugBoundsColor = [1.00f, 0.20f, 0.05f, 0.70f];
private enum float resizeGripHitSize = 10.0f;
private enum float resizeGripMarkerSize = 10.0f;
private enum float resizeGripLineInset = 6.0f;
private enum float fallbackTitleTextHeight = 16.0f;
private enum float windowContentMargin = 3.0f;
private enum float chromeTopInset = 7.0f;
private enum float defaultOpenTransitionSeconds = 0.12f;
private enum float defaultCloseTransitionSeconds = 0.10f;

/** Logical top-level window presentation state for future visual transitions. */
enum UiWindowTransitionState
{
    hidden,
    opening,
    visible,
    closing,
}

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
    bool stackable = true;                          ///< True when middle-clicking chrome toggles front/back stacking.
    bool showHeader = true;                         ///< True when the title/header band is rendered and hit-tested.
    bool showTitle = true;                          ///< True when the title text is rendered inside the header.
    bool showBorder = true;                         ///< True when the outer border is rendered and reserved for content.
    bool dragTracking;                              ///< True while a drag gesture is active.
    bool resizeTracking;                            ///< True while a resize gesture is active.
    UiResizeHandle resizeHandle = UiResizeHandle.none; ///< Active resize corner while a resize gesture is running.
    float headerHeight = 30.0f;                     ///< Height of the decorative header bar.
    float borderThickness = windowContentMargin;    ///< Content inset and draw thickness for the simple outer border.
    UiButton defaultButton;                         ///< Optional button activated by Enter while this window is modal.
    UiButton cancelButton;                          ///< Optional button activated by Escape while this window is modal.
    UiWindowTransitionState transitionState = UiWindowTransitionState.visible; ///< Current presentation transition state.
    float transitionProgress = 1.0f;                ///< Normalized progress from 0 to 1 for opening or closing.

    private UiContentBox contentRoot;               ///< Body widgets are kept in a separate root so chrome stays explicit.
    private UiHBox headerExtras;                    ///< Optional extra header widgets placed to the left of the close button.
    private UiButton closeButton;                   ///< Optional close button rendered in the header.
    private float headerExtrasWidth;                ///< Cached width of all extra header widgets.
    private float headerExtrasHeight;               ///< Cached height of all extra header widgets.
    private uint resizeButton;                      ///< Mouse button that owns the active resize gesture.
    private float openTransitionDuration = defaultOpenTransitionSeconds;
    private float closeTransitionDuration = defaultCloseTransitionSeconds;

    void delegate(float, float) onHeaderDragStart;              ///< Notified when a header drag starts.
    void delegate(float, float) onHeaderDragMove;               ///< Notified while a header drag is running.
    void delegate() onHeaderDragEnd;                            ///< Notified when a header drag ends.
    void delegate(UiResizeHandle) onResizeStart;                ///< Notified when a resize gesture starts.
    void delegate(UiResizeHandle, float, float) onResizeMove;   ///< Notified while a resize gesture is running.
    void delegate(UiResizeHandle) onResizeEnd;                  ///< Notified when a resize gesture ends.
    void delegate() onHeaderMiddleClick;                        ///< Notified when the middle mouse button clicks free window chrome.
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
     *   contentPaddingLeft = Left inset for the internal content root.
     *   contentPaddingTop = Top inset for the internal content root.
     *   contentPaddingRight = Right inset for the internal content root.
     *   contentPaddingBottom = Bottom inset for the internal content root.
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

        contentRoot = new UiContentBox(0.0f, headerHeight + borderThickness, width, max(height - headerHeight - borderThickness, 0.0f), contentPaddingLeft, contentPaddingTop, contentPaddingRight, contentPaddingBottom);
        super.add(contentRoot);

        headerExtras = new UiHBox(0.0f, 0.0f, 0.0f, 0.0f, 4.0f);

        if (closable)
            ensureCloseButton();

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

    /** Marks a body button as the default action for modal Enter handling. */
    void setDefaultButton(UiButton button)
    {
        defaultButton = button;
    }

    /** Marks a body button as the cancel action for modal Escape handling. */
    void setCancelButton(UiButton button)
    {
        cancelButton = button;
    }

    /** Activates the configured default action, if it is currently visible. */
    bool activateDefaultButton()
    {
        if (defaultButton is null || !defaultButton.visible)
            return false;

        defaultButton.activate();
        return true;
    }

    /** Activates the configured cancel action, if it is currently visible. */
    bool activateCancelButton()
    {
        if (cancelButton is null || !cancelButton.visible)
            return false;

        cancelButton.activate();
        return true;
    }

    /** Starts an opening transition and makes the window visible immediately. */
    void beginOpenTransition(float durationSeconds = defaultOpenTransitionSeconds)
    {
        openTransitionDuration = max(durationSeconds, 0.0f);
        visible = true;
        transitionProgress = openTransitionDuration <= 0.0f ? 1.0f : 0.0f;
        transitionState = transitionProgress >= 1.0f ? UiWindowTransitionState.visible : UiWindowTransitionState.opening;
    }

    /** Starts a closing transition. The window becomes hidden when it completes. */
    void beginCloseTransition(float durationSeconds = defaultCloseTransitionSeconds)
    {
        closeTransitionDuration = max(durationSeconds, 0.0f);
        transitionProgress = closeTransitionDuration <= 0.0f ? 1.0f : 0.0f;
        if (transitionProgress >= 1.0f)
        {
            visible = false;
            transitionState = UiWindowTransitionState.hidden;
        }
        else
        {
            transitionState = UiWindowTransitionState.closing;
        }
    }

    /** Returns true while an opening or closing transition is active. */
    bool hasActiveTransition() const
    {
        return transitionState == UiWindowTransitionState.opening || transitionState == UiWindowTransitionState.closing;
    }

    /** Returns the renderer-facing alpha for the current transition frame. */
    float presentationAlpha() const
    {
        final switch (transitionState)
        {
            case UiWindowTransitionState.hidden:
                return 0.0f;
            case UiWindowTransitionState.opening:
                return transitionProgress;
            case UiWindowTransitionState.visible:
                return 1.0f;
            case UiWindowTransitionState.closing:
                return max(0.0f, 1.0f - transitionProgress);
        }
    }

    /** Returns the renderer-facing scale for the current transition frame. */
    float presentationScale() const
    {
        return 0.96f + presentationAlpha() * 0.04f;
    }

    /** Returns the renderer-facing X translation for the current transition frame. */
    float presentationOffsetX() const
    {
        return 0.0f;
    }

    /** Returns the renderer-facing Y translation for the current transition frame. */
    float presentationOffsetY() const
    {
        return (1.0f - presentationAlpha()) * -6.0f;
    }

    /** Advances the window transition state without applying visual transforms yet. */
    bool tickTransition(float deltaSeconds)
    {
        if (!hasActiveTransition())
            return false;

        const duration = transitionState == UiWindowTransitionState.opening ? openTransitionDuration : closeTransitionDuration;
        const step = duration <= 0.0f ? 1.0f : max(deltaSeconds, 0.0f) / duration;
        transitionProgress = max(0.0f, transitionProgress + step);
        if (transitionProgress < 1.0f)
            return true;

        transitionProgress = 1.0f;
        if (transitionState == UiWindowTransitionState.opening)
            transitionState = UiWindowTransitionState.visible;
        else
        {
            transitionState = UiWindowTransitionState.hidden;
            visible = false;
        }

        return true;
    }

    /** Updates the interactive chrome flags at runtime.
     *
     * Params:
     *   sizeable = Enables the resize ring and resize hit testing.
     *   closable = Enables the close button in the header.
     *   dragable = Enables drag hit testing and drag header styling.
     * Returns:
     *   Nothing.
     */
    void setChromeFlags(bool sizeable, bool closable, bool dragable)
    {
        setChromeFlags(sizeable, closable, dragable, stackable);
    }

    /** Updates the interactive chrome flags at runtime.
     *
     * Params:
     *   sizeable = Enables the resize ring and resize hit testing.
     *   closable = Enables the close button in the header.
     *   dragable = Enables drag hit testing and drag header styling.
     *   stackable = Enables middle-click front/back stacking on free chrome.
     * Returns:
     *   Nothing.
     */
    void setChromeFlags(bool sizeable, bool closable, bool dragable, bool stackable)
    {
        this.sizeable = sizeable;
        this.closable = closable;
        this.dragable = dragable;
        this.stackable = stackable;
        if (closable)
            ensureCloseButton();
        updateChromeLayout();
    }

    /** Updates non-behavioral chrome visibility flags.
     *
     * Params:
     *   showHeader = Renders and hit-tests the header band.
     *   showTitle = Renders the title text inside the header.
     *   showBorder = Renders and reserves the outer border.
     * Returns:
     *   Nothing.
     */
    void setChromeVisibility(bool showHeader, bool showTitle, bool showBorder)
    {
        this.showHeader = showHeader;
        this.showTitle = showTitle;
        this.showBorder = showBorder;
        if (closable && showHeader)
            ensureCloseButton();
        if (!showHeader)
            dragTracking = false;
        if (!activeResizeRing())
        {
            resizeTracking = false;
            resizeHandle = UiResizeHandle.none;
            resizeButton = 0;
        }
        updateChromeLayout();
    }

    /** Returns the top-level non-content height that auto sizing must reserve. */
    float verticalChromeExtent() const
    {
        return contentTopInset() + contentBottomInset();
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
        contentRoot.layout(context);
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

            if (event.kind == UiPointerEventKind.buttonUp && event.button == resizeButton)
            {
                if (onResizeEnd !is null)
                    onResizeEnd(resizeHandle);
                logLine("UiWindow resize end: ", title, " [", resizeHandle, "]");
                resizeTracking = false;
                resizeHandle = UiResizeHandle.none;
                resizeButton = 0;
                return true;
            }
        }

        if (event.kind == UiPointerEventKind.buttonDown)
        {
            const handle = hitResizeHandle(event.x, event.y);
            if (handle != UiResizeHandle.none)
            {
                logLine("UiWindow resize hit: ", title, " [", handle, "] button ", event.button, " at ", event.x, ", ", event.y);
                resizeHandle = handle;
                resizeButton = event.button;
                resizeTracking = true;
                dragTracking = false;
                if (onResizeStart !is null)
                    onResizeStart(handle);
                return true;
            }

            if (activeCloseButton())
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

            if (showHeader && headerExtras.children.length > 0)
            {
                auto headerEvent = event;
                headerEvent.x -= x;
                headerEvent.y -= y;
                if (headerExtras.dispatchPointerEvent(headerEvent))
                    return true;
            }

            if (event.button == 2 && stackable && isInWindowChrome(event.x, event.y))
            {
                if (onHeaderMiddleClick !is null)
                    onHeaderMiddleClick();
                return true;
            }

            if (event.button == 1 && dragable && showHeader && isInDragHeader(event.x, event.y))
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

    /** Returns cursor intent for chrome or body widgets at the given point. */
    override UiCursorKind cursorAt(float localX, float localY)
    {
        if (!visible || !contains(localX, localY))
            return UiCursorKind.default_;

        updateChromeLayout();

        const handle = hitResizeHandle(localX, localY);
        if (handle != UiResizeHandle.none)
            return cursorForResizeHandle(handle);

        const windowX = localX - x;
        const windowY = localY - y;

        if (activeCloseButton())
        {
            const cursor = closeButton.cursorAt(windowX, windowY);
            if (cursor != UiCursorKind.default_)
                return cursor;
        }

        if (showHeader && headerExtras.children.length > 0)
        {
            const cursor = headerExtras.cursorAt(windowX, windowY);
            if (cursor != UiCursorKind.default_)
                return cursor;
        }

        if (dragable && showHeader && isInDragHeader(localX, localY))
            return UiCursorKind.move;

        return super.cursorAt(localX, localY);
    }

protected:
    override bool tickSelf(float deltaSeconds)
    {
        return tickTransition(deltaSeconds);
    }

    /** Draws the chrome and the title badge before the body children are rendered. */
    override void renderSelf(ref UiRenderContext context)
    {
        updateChromeLayout();

        const headerFill = showHeader ? headerColor : bodyColor;
        const bodyFill = bodyColor;
        const renderedHeaderHeight = showHeader ? headerHeight : 0.0f;

        const gripInset = activeResizeRing() ? resizeGripHitSize : 0.0f;
        float headerRightInset = gripInset;

        if (showHeader && headerExtras.children.length > 0)
            headerRightInset += headerExtrasWidth + headerExtras.spacing + 12.0f;

        if (activeCloseButton())
            headerRightInset += closeButton.width + 8.0f;

        appendWindowFrame(context, 0.0f, 0.0f, width, height, renderedHeaderHeight, bodyFill, headerFill, context.depthBase, gripInset, headerRightInset);

        if (activeResizeRing())
            appendResizeGrips(context);

        if (showHeader && showTitle)
        {
            const titleX = activeResizeRing() ? resizeGripHitSize + 6.0f : 10.0f;
            const titleY = max(0.0f, (headerHeight - titleTextHeight(context)) * 0.5f);
            appendTextLine(context, UiTextStyle.large, title, titleX, titleY, titleColor, context.depthBase - 0.001f);
        }

        if (showHeader && headerExtras.children.length > 0)
        {
            headerExtras.render(context);
        }

        if (activeCloseButton())
        {
            closeButton.render(context);
        }

        if (showBorder)
            appendWindowBorder(context, 0.0f, 0.0f, width, height, context.depthBase - 0.003f, borderThickness);
    }

    override float[4] debugBoundsColor() const
    {
        return cast(float[4])windowDebugBoundsColor;
    }

private:
    /** Positions the header controls so they stay clear of the resize grip. */
    void updateChromeLayout()
    {
        const closeWidth = activeCloseButton() ? closeButton.width : 0.0f;
        const closeGap = activeCloseButton() ? 4.0f : 0.0f;
        const gripReserve = activeResizeRing() ? resizeGripHitSize : 0.0f;

        headerExtras.width = headerExtrasWidth;
        headerExtras.height = headerExtrasHeight;
        headerExtras.x = max(10.0f, width - gripReserve - closeWidth - closeGap - headerExtrasWidth - 12.0f);
        headerExtras.y = chromeTopInset + 1.0f;

        contentRoot.x = contentLeftInset();
        contentRoot.y = contentTopInset();
        contentRoot.width = max(width - contentLeftInset() - contentRightInset(), 0.0f);
        contentRoot.height = max(height - contentTopInset() - contentBottomInset(), 0.0f);

        if (activeCloseButton())
        {
            closeButton.x = width - gripReserve - closeWidth - 3.0f;
            closeButton.y = max(0.0f, (headerHeight - closeButton.height) * 0.5f);
        }
    }

    /** Creates the built-in close button on demand. */
    void ensureCloseButton()
    {
        if (closeButton !is null)
            return;

        closeButton = new UiButton("X", 0.0f, 0.0f, 16.0f, 16.0f, [0.55f, 0.10f, 0.12f, 0.96f], [0.92f, 0.46f, 0.46f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f], UiTextStyle.small, 4.0f, 0.5f);
        closeButton.onClick = &handleCloseButton;
    }

    /** Returns the draw-time title text height used for vertical centering. */
    float titleTextHeight(ref UiRenderContext context) const
    {
        const atlas = context.atlasFor(UiTextStyle.large);
        return atlas is null ? fallbackTitleTextHeight : max(atlas.lineHeight, atlas.ascent + atlas.descent);
    }

    /** Draws the visual resize ring and corner markers around the window. */
    void appendResizeGrips(ref UiRenderContext context) const
    {
        const z = context.depthBase - 0.0005f;
        float[4] gripLine = [0.34f, 0.58f, 0.78f, 0.28f];
        float[4] gripLight = [0.72f, 0.88f, 1.00f, 0.46f];
        float[4] gripShadow = [0.04f, 0.06f, 0.08f, 0.30f];
        const marker = resizeGripMarkerSize;
        const inset = resizeGripLineInset;

        appendQuad(context, resizeGripHitSize, inset, width - resizeGripHitSize, inset + 1.0f, z, gripLine);
        appendQuad(context, resizeGripHitSize, height - inset - 1.0f, width - resizeGripHitSize, height - inset, z, gripLine);
        appendQuad(context, inset, resizeGripHitSize, inset + 1.0f, height - resizeGripHitSize, z, gripLine);
        appendQuad(context, width - inset - 1.0f, resizeGripHitSize, width - inset, height - resizeGripHitSize, z, gripLine);

        appendTriangle(context, 0.0f, 0.0f, marker, 0.0f, 0.0f, marker, z - 0.0005f, gripLight);
        appendTriangle(context, width, 0.0f, width - marker, 0.0f, width, marker, z - 0.0005f, gripLight);
        appendTriangle(context, 0.0f, height, marker, height, 0.0f, height - marker, z - 0.0005f, gripShadow);
        appendTriangle(context, width, height, width - marker, height, width, height - marker, z - 0.0005f, gripShadow);
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
        if (!showHeader || !isInWindowChrome(localX, localY) || localY >= y + headerHeight)
            return false;

        return true;
    }

    /** Returns whether the pointer lies in window chrome outside the content root. */
    bool isInWindowChrome(float localX, float localY) const
    {
        if (localX < x || localX >= x + width || localY < y || localY >= y + height)
            return false;

        if (localX >= x + contentRoot.x && localX < x + contentRoot.x + contentRoot.width &&
            localY >= y + contentRoot.y && localY < y + contentRoot.y + contentRoot.height)
        {
            return false;
        }

        if (activeResizeRing())
        {
            if (localX < x + resizeGripHitSize && localY < y + resizeGripHitSize)
                return false;

            if (localX >= x + width - resizeGripHitSize && localY < y + resizeGripHitSize)
                return false;

            if (localX < x + resizeGripHitSize && localY >= y + height - resizeGripHitSize)
                return false;

            if (localX >= x + width - resizeGripHitSize && localY >= y + height - resizeGripHitSize)
                return false;
        }

        if (activeCloseButton())
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
        if (!activeResizeRing())
            return UiResizeHandle.none;

        if (localX < x || localX >= x + width || localY < y || localY >= y + height)
            return UiResizeHandle.none;

        if (localX >= x && localX < x + resizeGripHitSize && localY >= y && localY < y + resizeGripHitSize)
            return UiResizeHandle.topLeft;
        if (localX >= x + width - resizeGripHitSize && localX < x + width && localY >= y && localY < y + resizeGripHitSize)
            return UiResizeHandle.topRight;
        if (localX >= x && localX < x + resizeGripHitSize && localY >= y + height - resizeGripHitSize && localY < y + height)
            return UiResizeHandle.bottomLeft;
        if (localX >= x + width - resizeGripHitSize && localX < x + width && localY >= y + height - resizeGripHitSize && localY < y + height)
            return UiResizeHandle.bottomRight;
        if (localY >= y && localY < y + resizeGripHitSize)
            return UiResizeHandle.top;
        if (localX >= x + width - resizeGripHitSize && localX < x + width)
            return UiResizeHandle.right;
        if (localY >= y + height - resizeGripHitSize && localY < y + height)
            return UiResizeHandle.bottom;
        if (localX >= x && localX < x + resizeGripHitSize)
            return UiResizeHandle.left;

        return UiResizeHandle.none;
    }

    bool activeResizeRing() const
    {
        return sizeable;
    }

    bool activeCloseButton() const
    {
        return closable && showHeader && closeButton !is null;
    }

    float contentLeftInset() const
    {
        return activeResizeRing() ? resizeGripHitSize : borderInset();
    }

    float contentRightInset() const
    {
        return activeResizeRing() ? resizeGripHitSize : borderInset();
    }

    float contentTopInset() const
    {
        if (showHeader)
            return headerHeight + borderInset();
        return activeResizeRing() ? resizeGripHitSize : borderInset();
    }

    float contentBottomInset() const
    {
        return activeResizeRing() ? resizeGripHitSize : borderInset();
    }

    float borderInset() const
    {
        return showBorder ? max(borderThickness, 0.0f) : 0.0f;
    }

}

@("UiWindow stretches direct content to the content root")
unittest
{
    auto window = new UiWindow("Test", 0.0f, 0.0f, 240.0f, 180.0f, [0.0f, 0.0f, 0.0f, 1.0f], [0.0f, 0.0f, 0.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f], false, false, false, 12.0f, 8.0f, 16.0f, 10.0f);
    auto content = new UiVBox();
    window.add(content);

    UiLayoutContext context;
    window.layoutWindow(context);

    assert(content.x == 12.0f);
    assert(content.y == 8.0f);
    assert(content.width == 240.0f - 6.0f - 12.0f - 16.0f);
    assert(content.height == 180.0f - window.headerHeight - 6.0f - 8.0f - 10.0f);
}

@("UiWindow keeps sizeable content clear of the resize ring")
unittest
{
    auto window = new UiWindow("Test", 0.0f, 0.0f, 240.0f, 180.0f, [0.0f, 0.0f, 0.0f, 1.0f], [0.0f, 0.0f, 0.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f], true, false, false, 12.0f, 8.0f, 16.0f, 10.0f);
    auto content = new UiVBox();
    window.add(content);

    UiLayoutContext context;
    window.layoutWindow(context);

    assert(content.x == 12.0f);
    assert(content.y == 8.0f);
    assert(content.width == 240.0f - resizeGripHitSize * 2.0f - 12.0f - 16.0f);
    assert(content.height == 180.0f - window.headerHeight - windowContentMargin - resizeGripHitSize - 8.0f - 10.0f);
}

@("UiWindow headerless content remains inside border")
unittest
{
    auto window = new UiWindow("Test", 0.0f, 0.0f, 240.0f, 180.0f, [0.0f, 0.0f, 0.0f, 1.0f], [0.0f, 0.0f, 0.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f], false, false, false, 12.0f, 8.0f, 16.0f, 10.0f);
    window.setChromeVisibility(false, false, true);
    auto content = new UiVBox();
    window.add(content);

    UiLayoutContext context;
    window.layoutWindow(context);

    assert(content.x == 12.0f);
    assert(content.y == 8.0f);
    assert(content.width == 240.0f - window.borderThickness * 2.0f - 12.0f - 16.0f);
    assert(content.height == 180.0f - window.borderThickness * 2.0f - 8.0f - 10.0f);
}

@("UiWindow borderless headerless content fills the window")
unittest
{
    auto window = new UiWindow("Test", 0.0f, 0.0f, 240.0f, 180.0f, [0.0f, 0.0f, 0.0f, 1.0f], [0.0f, 0.0f, 0.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f], false, false, false, 0.0f, 0.0f, 0.0f, 0.0f);
    window.setChromeVisibility(false, false, false);
    auto content = new UiVBox();
    window.add(content);

    UiLayoutContext context;
    window.layoutWindow(context);

    assert(content.x == 0.0f);
    assert(content.y == 0.0f);
    assert(content.width == 240.0f);
    assert(content.height == 180.0f);
}

@("UiWindow hidden chrome disables matching cursor regions")
unittest
{
    auto window = new UiWindow("Test", 10.0f, 20.0f, 240.0f, 180.0f, [0.0f, 0.0f, 0.0f, 1.0f], [0.0f, 0.0f, 0.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f], true, false, true);

    assert(window.cursorAt(12.0f, 22.0f) == UiCursorKind.resizeNwse);
    assert(window.cursorAt(40.0f, 32.0f) == UiCursorKind.move);

    window.setChromeFlags(false, false, true);
    window.setChromeVisibility(false, false, true);

    assert(window.cursorAt(12.0f, 22.0f) == UiCursorKind.default_);
    assert(window.cursorAt(40.0f, 32.0f) == UiCursorKind.default_);
}

@("UiWindow advances open and close transition states")
unittest
{
    auto window = new UiWindow("Test", 10.0f, 20.0f, 240.0f, 180.0f, [0.0f, 0.0f, 0.0f, 1.0f], [0.0f, 0.0f, 0.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f]);

    window.visible = false;
    window.beginOpenTransition(0.10f);
    assert(window.visible);
    assert(window.transitionState == UiWindowTransitionState.opening);
    assert(window.hasActiveTransition());

    assert(window.tickTransition(0.05f));
    assert(window.transitionState == UiWindowTransitionState.opening);
    assert(window.transitionProgress > 0.49f && window.transitionProgress < 0.51f);
    assert(window.presentationAlpha() > 0.49f && window.presentationAlpha() < 0.51f);
    assert(window.presentationScale() > 0.97f && window.presentationScale() < 0.99f);
    assert(window.presentationOffsetY() < 0.0f);

    assert(window.tickTransition(0.05f));
    assert(window.transitionState == UiWindowTransitionState.visible);
    assert(window.transitionProgress == 1.0f);
    assert(window.visible);
    assert(!window.hasActiveTransition());

    window.beginCloseTransition(0.10f);
    assert(window.transitionState == UiWindowTransitionState.closing);
    assert(window.visible);
    assert(window.presentationAlpha() == 1.0f);

    assert(window.tickTransition(0.10f));
    assert(window.transitionState == UiWindowTransitionState.hidden);
    assert(window.transitionProgress == 1.0f);
    assert(!window.visible);
    assert(window.presentationAlpha() == 0.0f);
}
