/** Screen-level owner for the rebuilt retained UI.
 *
 * The screen owns the persistent window objects, keeps the launcher window as
 * the global entry point, and routes pointer input to the visible windows in
 * front-to-back order.
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.ui.ui_screen;

import std.algorithm : max, min;
import std.format : format;

import demo_settings : DemoSettings;
import vulkan.font.font_legacy : FontAtlas;
import vulkan.pipeline : Vertex;
import vulkan.ui.ui_button : UiButton;
import vulkan.ui.ui_context : UiRenderContext, UiTextStyle;
import vulkan.ui.ui_event : UiPointerEvent, UiPointerEventKind, UiResizeHandle;
import vulkan.ui.ui_label : UiLabel, UiTextBlock;
import vulkan.ui.ui_layout : UiHBox, UiSpacer, UiVBox;
import vulkan.ui.ui_layout_context : UiLayoutContext;
import vulkan.ui.ui_window : UiWindow;
import vulkan.ui_layer : HudLayout, HudLayoutState, HudOverlayGeometry, HudWindowDrawRange, HudWindowRect;

private enum float windowMargin = 18.0f;
private enum float launcherWidth = 320.0f;
private enum float launcherHeight = 264.0f;
private enum float demoWidth = 340.0f;
private enum float demoHeight = 220.0f;
private enum float statusWidth = 348.0f;
private enum float statusHeight = 180.0f;
private enum float controlsWidth = 360.0f;
private enum float controlsHeight = 200.0f;
private enum float notesWidth = 340.0f;
private enum float notesHeight = 168.0f;
private enum float contentSpacing = 6.0f;
private enum float sectionSpacing = 8.0f;
private enum float buttonBodyAlpha = 0.96f;

private immutable float[4] launcherBodyColor = [0.10f, 0.12f, 0.16f, 0.96f];
private immutable float[4] launcherHeaderColor = [0.14f, 0.16f, 0.20f, 0.98f];
private immutable float[4] launcherTitleColor = [1.00f, 0.98f, 0.82f, 1.00f];
private immutable float[4] launcherButtonFill = [0.16f, 0.18f, 0.24f, 0.96f];
private immutable float[4] launcherButtonBorder = [0.20f, 0.56f, 0.98f, 1.00f];
private immutable float[4] launcherButtonText = [1.00f, 1.00f, 1.00f, 1.00f];

private immutable float[4] panelBodyColor = [0.10f, 0.12f, 0.16f, 0.95f];
private immutable float[4] panelHeaderColor = [0.14f, 0.16f, 0.20f, 0.98f];
private immutable float[4] panelTitleColor = [1.00f, 0.98f, 0.82f, 1.00f];
private immutable float[4] panelAccentColor = [0.72f, 0.96f, 1.00f, 1.00f];
private immutable float[4] panelTextColor = [1.00f, 1.00f, 1.00f, 1.00f];

/** Owns the launcher window and the toggleable demo windows. */
final class UiScreen
{
    /** Compatibility state kept while the renderer is switched over to the rebuilt GUI. */
    HudLayoutState layoutState;
    /** Compatibility draft kept for the old settings helpers during migration. */
    DemoSettings settingsDraft;
    /** Compatibility scene-drag flag kept for the old renderer helpers. */
    bool sceneMouseDragging;

    private float viewportWidth;
    private float viewportHeight;
    private const(FontAtlas)[] fontAtlases;
    private UiLayoutContext layoutContext;

    private UiWindow launcherWindow;
    private UiWindow demoWindow;
    private UiWindow statusWindow;
    private UiWindow controlsWindow;
    private UiWindow notesWindow;

    private UiVBox launcherContent;
    private UiVBox demoContent;
    private UiVBox statusContent;
    private UiVBox controlsContent;
    private UiVBox notesContent;

    private UiButton launcherDemoButton;
    private UiButton launcherStatusButton;
    private UiButton launcherControlsButton;
    private UiButton launcherNotesButton;

    private UiButton demoStatusButton;
    private UiButton demoControlsButton;
    private UiButton demoNotesButton;
    private UiButton demoHideButton;

    private UiLabel statusBuildLabel;
    private UiLabel statusFpsLabel;
    private UiLabel statusSceneLabel;
    private UiLabel statusModeLabel;
    private UiLabel statusViewportLabel;

    private bool launcherAnchored;
    private bool demoAnchored;
    private bool statusAnchored;
    private bool controlsAnchored;
    private bool notesAnchored;

    private UiWindow activeDragWindow;
    private UiWindow activeResizeWindow;
    private float dragOffsetX;
    private float dragOffsetY;
    private float resizeStartLeft;
    private float resizeStartTop;
    private float resizeStartWidth;
    private float resizeStartHeight;
    private UiResizeHandle resizeStartHandle;

    /** True after the built-in launcher close button is used. */
    bool quitRequested;

    /** Creates the persistent window tree for the rebuilt UI.
     *
     * Params:
     *   liveFonts = Font atlases used for layout and text rendering.
     * Returns:
     *   Nothing.
     */
    void initialize(const(FontAtlas)[] liveFonts)
    {
        fontAtlases = liveFonts;
        layoutState = HudLayoutState.init;
        settingsDraft = DemoSettings.init;
        sceneMouseDragging = false;

        buildLauncherWindow();
        buildDemoWindow();
        buildStatusWindow();
        buildControlsWindow();
        buildNotesWindow();

        launcherWindow.onClose = &requestQuit;
        demoWindow.onClose = () { demoWindow.visible = false; };
        statusWindow.onClose = () { statusWindow.visible = false; };
        controlsWindow.onClose = () { controlsWindow.visible = false; };
        notesWindow.onClose = () { notesWindow.visible = false; };

        updateWindowState();
    }

    /** Updates viewport-dependent placement and relays the latest runtime text.
     *
     * Params:
     *   extentWidth = Swapchain width in pixels.
     *   extentHeight = Swapchain height in pixels.
     *   fps = Last measured frame rate.
     *   currentShapeName = Name of the active scene object.
     *   currentRenderModeName = Name of the active render mode.
     *   buildVersion = Git describe string for the build.
     * Returns:
     *   Nothing.
     */
    void syncViewport(float extentWidth, float extentHeight, float fps, string currentShapeName, string currentRenderModeName, string buildVersion)
    {
        viewportWidth = extentWidth;
        viewportHeight = extentHeight;

        layoutState.statusVisible = statusWindow.visible;
        layoutState.sampleVisible = demoWindow.visible;
        layoutState.inputVisible = controlsWindow.visible;
        layoutState.centerVisible = notesWindow.visible;
        layoutState.settingsVisible = false;

        updateStatusText(fps, currentShapeName, currentRenderModeName, buildVersion);
        ensureWindowLayout();
    }

    /** Routes a pointer event through the visible windows.
     *
     * Params:
     *   event = Pointer event in screen coordinates.
     * Returns:
     *   `true` when a visible window handled the event.
     */
    bool dispatchPointerEvent(ref UiPointerEvent event)
    {
        auto eventHandled = false;

        foreach_reverse (window; windowsInFrontToBack())
        {
            if (!window.visible)
                continue;

            if (window.dispatchPointerEvent(event))
            {
                eventHandled = true;
                break;
            }
        }

        return eventHandled;
    }

    /** Returns whether a pointer position lies inside any visible window.
     *
     * Params:
     *   x = Pointer X coordinate in window pixels.
     *   y = Pointer Y coordinate in window pixels.
     * Returns:
     *   `true` if the pointer is over one of the visible windows.
     */
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

    /** Builds the overlay geometry for all visible windows.
     *
     * Params:
     *   extentWidth = Swapchain width in pixels.
     *   extentHeight = Swapchain height in pixels.
     *   fps = Last measured frame rate.
     *   currentShapeName = Name of the active scene object.
     *   currentRenderModeName = Name of the active render mode.
     *   buildVersion = Git describe string for the build.
     *   fontAtlases = Font atlases used for text rendering.
     * Returns:
     *   Overlay panels, text layers, and per-window draw ranges.
     */
    HudOverlayGeometry buildOverlayVertices(float extentWidth, float extentHeight, float fps, string currentShapeName, string currentRenderModeName, string buildVersion, const(FontAtlas)[] fontAtlases)
    {
        syncViewport(extentWidth, extentHeight, fps, currentShapeName, currentRenderModeName, buildVersion);

        HudOverlayGeometry geometry;
        geometry.panels = [];
        foreach (layerIndex; 0 .. geometry.textLayers.length)
            geometry.textLayers[layerIndex] = [];

        HudWindowDrawRange[] drawRanges;

        UiRenderContext context = UiRenderContext.init;
        context.extentWidth = extentWidth;
        context.extentHeight = extentHeight;
        context.originX = 0.0f;
        context.originY = 0.0f;
        context.depthBase = 0.10f;
        foreach (index; 0 .. context.fonts.length)
            context.fonts[index] = index < fontAtlases.length ? &fontAtlases[index] : null;
        context.panels = &geometry.panels;
        foreach (index; 0 .. context.textLayers.length)
            context.textLayers[index] = &geometry.textLayers[index];

        foreach (index, window; windowsInFrontToBack())
        {
            if (!window.visible)
                continue;

            HudWindowDrawRange range;
            range.panelsStart = cast(uint)geometry.panels.length;
            foreach (layerIndex; 0 .. geometry.textLayers.length)
                range.textStarts[layerIndex] = cast(uint)geometry.textLayers[layerIndex].length;

            context.depthBase = 0.10f - cast(float)index * 0.02f;
            window.render(context);

            range.panelsCount = cast(uint)(geometry.panels.length - range.panelsStart);
            foreach (layerIndex; 0 .. geometry.textLayers.length)
                range.textCounts[layerIndex] = cast(uint)(geometry.textLayers[layerIndex].length - range.textStarts[layerIndex]);

            drawRanges ~= range;
        }

        geometry.windows = drawRanges;
        return geometry;
    }

    /** Compatibility layout builder kept for the old renderer code during migration. */
    HudLayout buildLayout(float extentWidth, float extentHeight, float fps, float yawAngle, float pitchAngle, string shapeName, string renderModeName, string buildVersion, string platformName, uint vulkanApiVersion, ref HudLayoutState ignoredLayoutState, const(FontAtlas)[] liveFonts, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont, ref const(FontAtlas) largeFont)
    {
        syncViewport(extentWidth, extentHeight, fps, shapeName, renderModeName, buildVersion);

        HudLayout layout;
        layout.status = HudWindowRect(statusWindow.x, statusWindow.y, statusWindow.width, statusWindow.height);
        layout.modes = HudWindowRect(launcherWindow.x, launcherWindow.y, launcherWindow.width, launcherWindow.height);
        layout.sample = HudWindowRect(demoWindow.x, demoWindow.y, demoWindow.width, demoWindow.height);
        layout.input = HudWindowRect(controlsWindow.x, controlsWindow.y, controlsWindow.width, controlsWindow.height);
        layout.center = HudWindowRect(notesWindow.x, notesWindow.y, notesWindow.width, notesWindow.height);
        return layout;
    }

    /** Compatibility overlay builder kept for the old renderer code during migration. */
    HudOverlayGeometry buildOverlayVertices(float extentWidth, float extentHeight, float fps, float yawAngle, float pitchAngle, string shapeName, string renderModeName, string buildVersion, string platformName, uint vulkanApiVersion, void delegate() onFlatColor, void delegate() onLitTextured, void delegate() onWireframe, void delegate() onHiddenLine, void delegate() onPreviousShape, void delegate() onNextShape, void delegate() onOpenSettings, void delegate() onApplySettings, const(FontAtlas)[] liveFonts, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont, ref const(FontAtlas) largeFont)
    {
        return buildOverlayVertices(extentWidth, extentHeight, fps, shapeName, renderModeName, buildVersion, liveFonts);
    }

private:
    /** Builds the launcher and all toggle buttons. */
    void buildLauncherWindow()
    {
        launcherWindow = new UiWindow("WINDOWS", windowMargin, windowMargin, launcherWidth, launcherHeight, cast(float[4])launcherBodyColor, cast(float[4])launcherHeaderColor, cast(float[4])launcherTitleColor, false, true, true, 14.0f, 12.0f, 14.0f, 12.0f);

        launcherContent = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, contentSpacing);
        launcherDemoButton = new UiButton("TOGGLE DEMO WINDOW", 0.0f, 0.0f, 0.0f, 0.0f, cast(float[4])launcherButtonFill, cast(float[4])launcherButtonBorder, cast(float[4])launcherButtonText);
        launcherDemoButton.onClick = &toggleDemoWindow;
        launcherStatusButton = new UiButton("TOGGLE STATUS WINDOW", 0.0f, 0.0f, 0.0f, 0.0f, cast(float[4])launcherButtonFill, cast(float[4])launcherButtonBorder, cast(float[4])launcherButtonText);
        launcherStatusButton.onClick = &toggleStatusWindow;
        launcherControlsButton = new UiButton("TOGGLE CONTROLS WINDOW", 0.0f, 0.0f, 0.0f, 0.0f, cast(float[4])launcherButtonFill, cast(float[4])launcherButtonBorder, cast(float[4])launcherButtonText);
        launcherControlsButton.onClick = &toggleControlsWindow;
        launcherNotesButton = new UiButton("TOGGLE NOTES WINDOW", 0.0f, 0.0f, 0.0f, 0.0f, cast(float[4])launcherButtonFill, cast(float[4])launcherButtonBorder, cast(float[4])launcherButtonText);
        launcherNotesButton.onClick = &toggleNotesWindow;

        launcherContent.add(launcherDemoButton);
        launcherContent.add(new UiSpacer(0.0f, sectionSpacing));
        launcherContent.add(launcherStatusButton);
        launcherContent.add(new UiSpacer(0.0f, sectionSpacing));
        launcherContent.add(launcherControlsButton);
        launcherContent.add(new UiSpacer(0.0f, sectionSpacing));
        launcherContent.add(launcherNotesButton);
        launcherWindow.add(launcherContent);
    }

    /** Builds the demo sandbox window with additional buttons. */
    void buildDemoWindow()
    {
        demoWindow = new UiWindow("BUTTON SANDBOX", windowMargin, windowMargin + launcherHeight + windowMargin, demoWidth, demoHeight, cast(float[4])panelBodyColor, cast(float[4])panelHeaderColor, cast(float[4])panelTitleColor, true, true, true, 14.0f, 12.0f, 14.0f, 12.0f);

        demoContent = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, contentSpacing);
        demoContent.add(new UiLabel("A BUTTON ROW CAN ALSO CONTROL WINDOW VISIBILITY.", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])panelAccentColor));

        demoStatusButton = new UiButton("SHOW STATUS", 0.0f, 0.0f, 0.0f, 0.0f, cast(float[4])launcherButtonFill, cast(float[4])launcherButtonBorder, cast(float[4])launcherButtonText);
        demoStatusButton.onClick = &toggleStatusWindow;
        demoControlsButton = new UiButton("SHOW CONTROLS", 0.0f, 0.0f, 0.0f, 0.0f, cast(float[4])launcherButtonFill, cast(float[4])launcherButtonBorder, cast(float[4])launcherButtonText);
        demoControlsButton.onClick = &toggleControlsWindow;
        demoNotesButton = new UiButton("SHOW NOTES", 0.0f, 0.0f, 0.0f, 0.0f, cast(float[4])launcherButtonFill, cast(float[4])launcherButtonBorder, cast(float[4])launcherButtonText);
        demoNotesButton.onClick = &toggleNotesWindow;
        demoHideButton = new UiButton("HIDE THIS WINDOW", 0.0f, 0.0f, 0.0f, 0.0f, cast(float[4])launcherButtonFill, cast(float[4])launcherButtonBorder, cast(float[4])launcherButtonText);
        demoHideButton.onClick = () { demoWindow.visible = false; };

        demoContent.add(demoStatusButton);
        demoContent.add(demoControlsButton);
        demoContent.add(demoNotesButton);
        demoContent.add(demoHideButton);
        demoWindow.add(demoContent);
    }

    /** Builds the live status window. */
    void buildStatusWindow()
    {
        statusWindow = new UiWindow("STATUS", viewportWidth > 0.0f ? max(viewportWidth - statusWidth - windowMargin, windowMargin) : windowMargin, windowMargin, statusWidth, statusHeight, cast(float[4])panelBodyColor, cast(float[4])panelHeaderColor, cast(float[4])panelTitleColor, true, true, true, 14.0f, 12.0f, 14.0f, 12.0f);

        statusContent = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, contentSpacing);
        statusBuildLabel = new UiLabel("BUILD: pending", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])panelTextColor);
        statusFpsLabel = new UiLabel("FPS: pending", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])panelTextColor);
        statusSceneLabel = new UiLabel("SCENE: pending", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])panelTextColor);
        statusModeLabel = new UiLabel("MODE: pending", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])panelTextColor);
        statusViewportLabel = new UiLabel("VIEWPORT: pending", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])panelAccentColor);

        statusContent.add(statusBuildLabel);
        statusContent.add(statusFpsLabel);
        statusContent.add(statusSceneLabel);
        statusContent.add(statusModeLabel);
        statusContent.add(statusViewportLabel);
        statusWindow.add(statusContent);
    }

    /** Builds the keyboard-and-mouse help window. */
    void buildControlsWindow()
    {
        controlsWindow = new UiWindow("CONTROLS", windowMargin, viewportHeight > 0.0f ? max(viewportHeight - controlsHeight - windowMargin, windowMargin) : windowMargin, controlsWidth, controlsHeight, cast(float[4])panelBodyColor, cast(float[4])panelHeaderColor, cast(float[4])panelTitleColor, true, true, true, 14.0f, 12.0f, 14.0f, 12.0f);

        controlsContent = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, contentSpacing);
        controlsContent.add(new UiLabel("LEFT CLICK AND DRAG THE HEADER TO MOVE A WINDOW.", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])panelTextColor));
        controlsContent.add(new UiLabel("USE THE CORNERS TO RESIZE THE WINDOW.", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])panelTextColor));
        controlsContent.add(new UiLabel("THE LAUNCHER BUTTONS OPEN OR CLOSE EACH WINDOW.", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])panelTextColor));
        controlsContent.add(new UiLabel("ESC STILL EXITS THE APPLICATION.", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])panelAccentColor));
        controlsWindow.add(controlsContent);
    }

    /** Builds the notes window that explains the rebuilt UI direction. */
    void buildNotesWindow()
    {
        notesWindow = new UiWindow("NOTES", viewportWidth > 0.0f ? max(viewportWidth - notesWidth - windowMargin, windowMargin) : windowMargin, viewportHeight > 0.0f ? max(viewportHeight - notesHeight - windowMargin, windowMargin) : windowMargin, notesWidth, notesHeight, cast(float[4])panelBodyColor, cast(float[4])panelHeaderColor, cast(float[4])panelTitleColor, true, true, true, 14.0f, 12.0f, 14.0f, 12.0f);

        notesContent = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, contentSpacing);
        notesContent.add(new UiLabel("THIS SCREEN IS THE NEW GUI SHELL.", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])panelTextColor));
        notesContent.add(new UiLabel("THE LAUNCHER WINDOW IS THE ENTRY POINT.", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])panelTextColor));
        notesContent.add(new UiLabel("ALL SECONDARY WINDOWS ARE DRAGGABLE AND RESIZABLE.", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])panelAccentColor));
        notesWindow.add(notesContent);
    }

    /** Updates the runtime labels shown in the status window. */
    void updateStatusText(float fps, string currentShapeName, string currentRenderModeName, string buildVersion)
    {
        statusBuildLabel.text = format("BUILD: %s", buildVersion);
        statusFpsLabel.text = format("FPS: %.1f", fps);
        statusSceneLabel.text = format("SCENE: %s", currentShapeName);
        statusModeLabel.text = format("MODE: %s", currentRenderModeName);
        statusViewportLabel.text = format("VIEWPORT: %.0f x %.0f", viewportWidth, viewportHeight);
    }

    /** Ensures all windows have sensible positions and measured content sizes. */
    void ensureWindowLayout()
    {
        if (viewportWidth <= 0.0f || viewportHeight <= 0.0f)
            return;

        layoutAllWindows();
        anchorWindows();
        clampWindowsToViewport();
    }

    /** Measures the persistent window contents with the current font atlases. */
    void layoutAllWindows()
    {
        if (fontAtlases.length == 0)
            return;

        layoutContext = buildLayoutContext(fontAtlases);
        launcherWindow.layoutWindow(layoutContext);
        demoWindow.layoutWindow(layoutContext);
        statusWindow.layoutWindow(layoutContext);
        controlsWindow.layoutWindow(layoutContext);
        notesWindow.layoutWindow(layoutContext);
    }

    /** Establishes the first reasonable position for each window. */
    void anchorWindows()
    {
        if (!launcherAnchored)
        {
            launcherWindow.x = windowMargin;
            launcherWindow.y = windowMargin;
            launcherAnchored = true;
        }

        if (!demoAnchored)
        {
            demoWindow.x = windowMargin;
            demoWindow.y = launcherWindow.y + launcherWindow.height + windowMargin;
            demoAnchored = true;
        }

        if (!statusAnchored)
        {
            statusWindow.x = viewportWidth > statusWindow.width ? viewportWidth - statusWindow.width - windowMargin : windowMargin;
            statusWindow.y = windowMargin;
            statusAnchored = true;
        }

        if (!controlsAnchored)
        {
            controlsWindow.x = viewportWidth > controlsWindow.width ? viewportWidth - controlsWindow.width - windowMargin : windowMargin;
            controlsWindow.y = viewportHeight > controlsWindow.height ? viewportHeight - controlsWindow.height - windowMargin : windowMargin;
            controlsAnchored = true;
        }

        if (!notesAnchored)
        {
            notesWindow.x = viewportWidth > notesWindow.width ? (viewportWidth - notesWindow.width) * 0.5f : windowMargin;
            notesWindow.y = viewportHeight > notesWindow.height ? (viewportHeight - notesWindow.height) * 0.5f : windowMargin;
            notesAnchored = true;
        }
    }

    /** Clamps all visible windows to the current viewport. */
    void clampWindowsToViewport()
    {
        clampWindowToViewport(launcherWindow);
        clampWindowToViewport(demoWindow);
        clampWindowToViewport(statusWindow);
        clampWindowToViewport(controlsWindow);
        clampWindowToViewport(notesWindow);
    }

    /** Clamps a single window to the current viewport bounds. */
    void clampWindowToViewport(UiWindow window)
    {
        if (window is null)
            return;

        const maximumLeft = viewportWidth > window.width ? viewportWidth - window.width : 0.0f;
        const maximumTop = viewportHeight > window.height ? viewportHeight - window.height : 0.0f;
        window.x = clampFloat(window.x, 0.0f, maximumLeft);
        window.y = clampFloat(window.y, 0.0f, maximumTop);
    }

public:

    /** Returns the persistent windows from back to front. */
    UiWindow[] windowsInFrontToBack()
    {
        return [launcherWindow, demoWindow, statusWindow, controlsWindow, notesWindow];
    }

    /** Returns the persistent windows from back to front. */
    const(UiWindow)[] windowsInFrontToBack() const
    {
        return [launcherWindow, demoWindow, statusWindow, controlsWindow, notesWindow];
    }

    /** Switches the demo window on or off. */
    void toggleDemoWindow()
    {
        toggleWindow(demoWindow);
    }

    /** Switches the status window on or off. */
    void toggleStatusWindow()
    {
        toggleWindow(statusWindow);
    }

    /** Switches the controls window on or off. */
    void toggleControlsWindow()
    {
        toggleWindow(controlsWindow);
    }

    /** Switches the notes window on or off. */
    void toggleNotesWindow()
    {
        toggleWindow(notesWindow);
    }

    /** Sets the close-button action on the launcher window. */
    void requestQuit()
    {
        quitRequested = true;
    }

    /** Ends any active drag or resize interaction. */
    void endWindowInteraction()
    {
        activeDragWindow = null;
        activeResizeWindow = null;
        resizeStartHandle = UiResizeHandle.none;
    }

    /** Compatibility hook kept while the renderer is being migrated. */
    void openSettingsDialog(const(DemoSettings)* liveSettings)
    {
        if (liveSettings !is null)
            settingsDraft = *liveSettings;

        toggleDemoWindow();
    }

    /** Compatibility hook kept while the renderer is being migrated. */
    void toggleSettingsDialog(const(DemoSettings)* liveSettings)
    {
        if (liveSettings !is null)
            settingsDraft = *liveSettings;

        toggleDemoWindow();
    }

    /** Switches a window's visibility. */
    void toggleWindow(UiWindow window)
    {
        if (window is null)
            return;

        window.visible = !window.visible;
        ensureWindowLayout();
    }

    /** Stores a drag start for a window title bar. */
    void beginWindowDrag(UiWindow window, float cursorX, float cursorY)
    {
        activeDragWindow = window;
        activeResizeWindow = null;
        dragOffsetX = cursorX - window.x;
        dragOffsetY = cursorY - window.y;
    }

    /** Updates the current drag operation. */
    void updateWindowDrag(float cursorX, float cursorY)
    {
        if (activeDragWindow is null)
            return;

        const newLeft = cursorX - dragOffsetX;
        const newTop = cursorY - dragOffsetY;
        const maximumLeft = viewportWidth > activeDragWindow.width ? viewportWidth - activeDragWindow.width : 0.0f;
        const maximumTop = viewportHeight > activeDragWindow.height ? viewportHeight - activeDragWindow.height : 0.0f;
        activeDragWindow.x = clampFloat(newLeft, 0.0f, maximumLeft);
        activeDragWindow.y = clampFloat(newTop, 0.0f, maximumTop);
    }

    /** Stores a resize start for a window corner grip. */
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

    /** Updates the current resize operation. */
    void updateWindowResize(float cursorX, float cursorY)
    {
        if (activeResizeWindow is null)
            return;

        const minimumWidth = 240.0f;
        const minimumHeight = 160.0f;
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
                const availableRight = viewportWidth > resizeStartLeft ? viewportWidth - resizeStartLeft : minimumWidth;
                const newTop = clampFloat(cursorY, 0.0f, startBottom - minimumHeight);
                activeResizeWindow.y = newTop;
                activeResizeWindow.width = clampFloat(cursorX - resizeStartLeft, minimumWidth, availableRight);
                activeResizeWindow.height = startBottom - newTop;
                break;
            }
            case UiResizeHandle.bottomLeft:
            {
                const availableBottom = viewportHeight > resizeStartTop ? viewportHeight - resizeStartTop : minimumHeight;
                const newLeft = clampFloat(cursorX, 0.0f, startRight - minimumWidth);
                activeResizeWindow.x = newLeft;
                activeResizeWindow.width = startRight - newLeft;
                activeResizeWindow.height = clampFloat(cursorY - resizeStartTop, minimumHeight, availableBottom);
                break;
            }
            case UiResizeHandle.bottomRight:
            {
                const availableWidth = viewportWidth > resizeStartLeft ? viewportWidth - resizeStartLeft : minimumWidth;
                const availableHeight = viewportHeight > resizeStartTop ? viewportHeight - resizeStartTop : minimumHeight;
                activeResizeWindow.width = clampFloat(cursorX - resizeStartLeft, minimumWidth, availableWidth);
                activeResizeWindow.height = clampFloat(cursorY - resizeStartTop, minimumHeight, availableHeight);
                break;
            }
            case UiResizeHandle.none:
                break;
        }

        clampWindowToViewport(activeResizeWindow);
    }

    /** Updates the launcher and demo window layout helpers. */
    void updateWindowState()
    {
        launcherWindow.visible = true;
        demoWindow.visible = false;
        statusWindow.visible = false;
        controlsWindow.visible = false;
        notesWindow.visible = false;
    }

    /** Creates the layout context for the current font atlases. */
    UiLayoutContext buildLayoutContext(const(FontAtlas)[] liveFonts) const
    {
        UiLayoutContext context;
        foreach (index; 0 .. context.fonts.length)
            context.fonts[index] = index < liveFonts.length ? &liveFonts[index] : null;
        return context;
    }

    /** Clamps a floating-point value to a closed interval. */
    static float clampFloat(float value, float minimum, float maximum)
    {
        return value < minimum ? minimum : (value > maximum ? maximum : value);
    }
}

@("UiScreen toggles window visibility through launcher buttons")
unittest
{
    UiScreen screen = new UiScreen();
    screen.initialize([]);

    assert(screen.containsPointer(20.0f, 20.0f));
    screen.toggleDemoWindow();
    assert(screen.demoWindow.visible);
    screen.toggleDemoWindow();
    assert(!screen.demoWindow.visible);
}