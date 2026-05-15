/** Screen-level owner for the rebuilt retained UI.
 *
 * The screen owns the persistent window objects, keeps the init window as the
 * global entry point, and routes pointer input to the visible windows in
 * front-to-back order.
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.ui.ui_screen;

import std.algorithm : max;
import std.format : format;

import demo_settings : DemoSettings;
import logging : logLine;
import vulkan.font.font_legacy : FontAtlas;
import vulkan.engine.pipeline : Vertex;
import vulkan.ui.ui_button : UiButton;
import vulkan.ui.ui_context : UiRenderContext, UiTextStyle;
import vulkan.ui.ui_event : UiPointerEvent, UiPointerEventKind, UiResizeHandle;
import vulkan.ui.ui_label : UiLabel;
import vulkan.ui.ui_layout : UiHBox, UiSpacer, UiVBox;
import vulkan.ui.ui_layout_context : UiLayoutContext;
import vulkan.ui.ui_window : UiWindow;
import vulkan.ui.ui_widget : UiWidget;
import vulkan.ui_layer : HudLayout, HudLayoutState, HudOverlayGeometry, HudWindowDrawRange, HudWindowRect, LayoutDemoWindow, buildLayoutDemoWindow;

private enum float windowMargin = 18.0f;
private enum float initWidth = 352.0f;
private enum float initHeight = 258.0f;
private enum float helpWidth = 388.0f;
private enum float helpHeight = 214.0f;
private enum float statusWidth = 348.0f;
private enum float statusHeight = 184.0f;
private enum float settingsWidth = 372.0f;
private enum float settingsHeight = 188.0f;
private enum float testWindowWidth = 420.0f;
private enum float testWindowHeight = 280.0f;
private enum float contentSpacing = 6.0f;
private enum float sectionSpacing = 8.0f;
private enum float probeSpacing = 10.0f;
private enum float probeMargin = 12.0f;
private enum float windowContentPaddingX = 17.0f;
private enum float windowContentPaddingY = 15.0f;

private immutable float[4] initBodyColor = [0.10f, 0.12f, 0.16f, 0.96f];
private immutable float[4] initHeaderColor = [0.14f, 0.16f, 0.20f, 0.98f];
private immutable float[4] initTitleColor = [1.00f, 0.98f, 0.82f, 1.00f];
private immutable float[4] initButtonFill = [0.16f, 0.18f, 0.24f, 0.96f];
private immutable float[4] initButtonBorder = [0.20f, 0.56f, 0.98f, 1.00f];
private immutable float[4] initButtonText = [1.00f, 1.00f, 1.00f, 1.00f];

private immutable float[4] helpBodyColor = [0.10f, 0.12f, 0.16f, 0.95f];
private immutable float[4] helpHeaderColor = [0.14f, 0.16f, 0.20f, 0.98f];
private immutable float[4] helpTitleColor = [1.00f, 0.98f, 0.82f, 1.00f];
private immutable float[4] helpAccentColor = [0.72f, 0.96f, 1.00f, 1.00f];
private immutable float[4] helpTextColor = [1.00f, 1.00f, 1.00f, 1.00f];

private immutable float[4] statusBodyColor = [0.10f, 0.12f, 0.16f, 0.95f];
private immutable float[4] statusHeaderColor = [0.14f, 0.16f, 0.20f, 0.98f];
private immutable float[4] statusTitleColor = [1.00f, 0.98f, 0.82f, 1.00f];
private immutable float[4] statusAccentColor = [0.72f, 0.96f, 1.00f, 1.00f];
private immutable float[4] statusTextColor = [1.00f, 1.00f, 1.00f, 1.00f];

private immutable float[4] settingsBodyColor = [0.10f, 0.12f, 0.16f, 0.95f];
private immutable float[4] settingsHeaderColor = [0.14f, 0.16f, 0.20f, 0.98f];
private immutable float[4] settingsTitleColor = [1.00f, 0.98f, 0.82f, 1.00f];
private immutable float[4] settingsAccentColor = [0.86f, 0.96f, 1.00f, 1.00f];
private immutable float[4] settingsTextColor = [1.00f, 1.00f, 1.00f, 1.00f];

private immutable float[4] probeFillA = [0.17f, 0.20f, 0.28f, 0.96f];
private immutable float[4] probeFillB = [0.14f, 0.24f, 0.20f, 0.96f];
private immutable float[4] probeFillC = [0.24f, 0.16f, 0.20f, 0.96f];
private immutable float[4] probeFillD = [0.18f, 0.18f, 0.18f, 0.96f];
private immutable float[4] probeBorderA = [0.20f, 0.56f, 0.98f, 1.00f];
private immutable float[4] probeBorderB = [0.34f, 0.82f, 0.46f, 1.00f];
private immutable float[4] probeBorderC = [0.92f, 0.46f, 0.46f, 1.00f];
private immutable float[4] probeBorderD = [0.82f, 0.72f, 0.28f, 1.00f];

final class UiScreen
{
    HudLayoutState layoutState;
    DemoSettings settingsDraft;
    bool sceneMouseDragging;

    private float viewportWidth;
    private float viewportHeight;
    private const(FontAtlas)[] fontAtlases;
    private UiLayoutContext layoutContext;

    private UiWindow initWindow;
    private UiWindow helpWindow;
    private UiWindow statusWindow;
    private UiWindow settingsWindow;
    private LayoutDemoWindow[] testWindows;
    private UiVBox initContent;
    private UiVBox helpContent;
    private UiVBox statusContent;
    private UiVBox settingsContent;
    private UiButton initHelpButton;
    private UiButton initStatusButton;
    private UiButton initSettingsButton;
    private UiButton initTestButton;

    private UiLabel helpTitleLabel;
    private UiLabel helpIntroLabel;
    private UiLabel helpLayoutLabel;
    private UiLabel helpCloseLabel;

    private UiLabel statusBuildLabel;
    private UiLabel statusFpsLabel;
    private UiLabel statusSceneLabel;
    private UiLabel statusModeLabel;
    private UiLabel statusViewportLabel;

    private UiLabel settingsTitleLabel;
    private UiLabel settingsIntroLabel;
    private UiLabel settingsProfileLabel;
    private UiLabel settingsPreviewLabel;

    private bool initAnchored;
    private bool helpAnchored;
    private bool statusAnchored;
    private bool settingsAnchored;

    private UiWindow activeDragWindow;
    private UiWindow activeResizeWindow;
    private float dragOffsetX;
    private float dragOffsetY;
    private float resizeStartLeft;
    private float resizeStartTop;
    private float resizeStartWidth;
    private float resizeStartHeight;
    private UiResizeHandle resizeStartHandle;
    private uint nextTestWindowSerial = 1;

    bool quitRequested;

    void initialize(const(FontAtlas)[] liveFonts)
    {
        fontAtlases = liveFonts;
        layoutState = HudLayoutState.init;
        settingsDraft = DemoSettings.init;
        sceneMouseDragging = false;
        testWindows = [];

        buildInitWindow();
        buildHelpWindow();
        buildStatusWindow();
        buildSettingsWindow();
        autoSizeWindow(initWindow, initContent, windowContentPaddingX, windowContentPaddingY, windowContentPaddingX, windowContentPaddingY, initWidth, initHeight);
        autoSizeWindow(helpWindow, helpContent, windowContentPaddingX, windowContentPaddingY, windowContentPaddingX, windowContentPaddingY, helpWidth, helpHeight);
        autoSizeWindow(statusWindow, statusContent, windowContentPaddingX, windowContentPaddingY, windowContentPaddingX, windowContentPaddingY, statusWidth, statusHeight);
        autoSizeWindow(settingsWindow, settingsContent, windowContentPaddingX, windowContentPaddingY, windowContentPaddingX, windowContentPaddingY, settingsWidth, settingsHeight);
        updateWindowState();
        ensureWindowLayout();
    }

    void syncViewport(float extentWidth, float extentHeight, float fps, string currentShapeName, string currentRenderModeName, string buildVersion)
    {
        viewportWidth = extentWidth;
        viewportHeight = extentHeight;

        layoutState.statusVisible = statusWindow.visible;
        layoutState.sampleVisible = hasVisibleTestWindow();
        layoutState.inputVisible = helpWindow.visible;
        layoutState.centerVisible = settingsWindow.visible;
        layoutState.settingsVisible = settingsWindow.visible;

        updateStatusText(fps, currentShapeName, currentRenderModeName, buildVersion);
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

    HudOverlayGeometry buildOverlayVertices(float extentWidth, float extentHeight, float fps, string currentShapeName, string currentRenderModeName, string buildVersion, const(FontAtlas)[] liveFonts)
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
            context.fonts[index] = index < liveFonts.length ? &liveFonts[index] : null;
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

    HudLayout buildLayout(float extentWidth, float extentHeight, float fps, float yawAngle, float pitchAngle, string shapeName, string renderModeName, string buildVersion, string platformName, uint vulkanApiVersion, ref HudLayoutState ignoredLayoutState, const(FontAtlas)[] liveFonts, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont, ref const(FontAtlas) largeFont)
    {
        syncViewport(extentWidth, extentHeight, fps, shapeName, renderModeName, buildVersion);

        HudLayout layout;
        layout.status = HudWindowRect(statusWindow.x, statusWindow.y, statusWindow.width, statusWindow.height);
        layout.modes = HudWindowRect(initWindow.x, initWindow.y, initWindow.width, initWindow.height);
        layout.sample = testWindows.length > 0 ? HudWindowRect(testWindows[0].window.x, testWindows[0].window.y, testWindows[0].window.width, testWindows[0].window.height) : HudWindowRect.init;
        layout.input = HudWindowRect(helpWindow.x, helpWindow.y, helpWindow.width, helpWindow.height);
        layout.center = HudWindowRect(settingsWindow.x, settingsWindow.y, settingsWindow.width, settingsWindow.height);
        return layout;
    }

    HudOverlayGeometry buildOverlayVertices(float extentWidth, float extentHeight, float fps, float yawAngle, float pitchAngle, string shapeName, string renderModeName, string buildVersion, string platformName, uint vulkanApiVersion, void delegate() onFlatColor, void delegate() onLitTextured, void delegate() onWireframe, void delegate() onHiddenLine, void delegate() onPreviousShape, void delegate() onNextShape, void delegate() onOpenSettings, void delegate() onApplySettings, const(FontAtlas)[] liveFonts, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont, ref const(FontAtlas) largeFont)
    {
        return buildOverlayVertices(extentWidth, extentHeight, fps, shapeName, renderModeName, buildVersion, liveFonts);
    }

    UiWindow[] windowsInFrontToBack()
    {
        UiWindow[] windows = [initWindow, helpWindow, statusWindow, settingsWindow];
        foreach (demoWindow; testWindows)
            windows ~= demoWindow.window;
        return windows;
    }

    const(UiWindow)[] windowsInFrontToBack() const
    {
        const(UiWindow)[] windows = [initWindow, helpWindow, statusWindow, settingsWindow];
        foreach (demoWindow; testWindows)
            windows ~= demoWindow.window;
        return windows;
    }

    void toggleHelpWindow()
    {
        toggleWindow(helpWindow);
    }

    void toggleStatusWindow()
    {
        toggleWindow(statusWindow);
    }

    void toggleSettingsWindow()
    {
        toggleWindow(settingsWindow);
    }

    void requestQuit()
    {
        quitRequested = true;
    }

    void endWindowInteraction()
    {
        activeDragWindow = null;
        activeResizeWindow = null;
        resizeStartHandle = UiResizeHandle.none;
    }

    void openSettingsDialog(const(DemoSettings)* liveSettings)
    {
        if (liveSettings !is null)
            settingsDraft = *liveSettings;
        toggleSettingsWindow();
    }

    void toggleSettingsDialog(const(DemoSettings)* liveSettings)
    {
        if (liveSettings !is null)
            settingsDraft = *liveSettings;
        toggleSettingsWindow();
    }

    void toggleWindow(UiWindow window)
    {
        if (window is null)
            return;

        window.visible = !window.visible;
        logLine("UiWindow toggle: ", window.title, " -> ", window.visible ? "open" : "closed");

        if (!window.visible && (window is activeDragWindow || window is activeResizeWindow))
            endWindowInteraction();

        ensureWindowLayout();
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
        const maximumLeft = viewportWidth > activeDragWindow.width ? viewportWidth - activeDragWindow.width : 0.0f;
        const maximumTop = viewportHeight > activeDragWindow.height ? viewportHeight - activeDragWindow.height : 0.0f;
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

    void updateWindowState()
    {
        initWindow.visible = true;
        helpWindow.visible = false;
        statusWindow.visible = false;
        settingsWindow.visible = false;
    }

    UiLayoutContext buildLayoutContext(const(FontAtlas)[] liveFonts) const
    {
        UiLayoutContext context;
        foreach (index; 0 .. context.fonts.length)
            context.fonts[index] = index < liveFonts.length ? &liveFonts[index] : null;
        return context;
    }

    static float clampFloat(float value, float minimum, float maximum)
    {
        return value < minimum ? minimum : (value > maximum ? maximum : value);
    }

    void autoSizeWindow(UiWindow window, UiWidget content, float paddingLeft, float paddingTop, float paddingRight, float paddingBottom, float minimumWidth, float minimumHeight)
    {
        if (window is null || content is null || fontAtlases.length == 0)
            return;

        auto sizeContext = buildLayoutContext(fontAtlases);
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

    bool hasVisibleTestWindow() const
    {
        foreach (demoWindow; testWindows)
        {
            if (demoWindow.window.visible)
                return true;
        }

        return false;
    }

    void buildInitWindow()
    {
        initWindow = new UiWindow("Sdl2-Vulkan-Demo", windowMargin, windowMargin, initWidth, initHeight, cast(float[4])initBodyColor, cast(float[4])initHeaderColor, cast(float[4])initTitleColor, true, true, true, 14.0f, 12.0f, 14.0f, 12.0f);

        initContent = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, contentSpacing);
        initHelpButton = new UiButton("Help ein- oder ausblenden", 0.0f, 0.0f, 0.0f, 0.0f, cast(float[4])initButtonFill, cast(float[4])initButtonBorder, cast(float[4])initButtonText);
        initHelpButton.onClick = &toggleHelpWindow;
        initStatusButton = new UiButton("Status ein- oder ausblenden", 0.0f, 0.0f, 0.0f, 0.0f, cast(float[4])initButtonFill, cast(float[4])initButtonBorder, cast(float[4])initButtonText);
        initStatusButton.onClick = &toggleStatusWindow;
        initSettingsButton = new UiButton("Einstellungen ein- oder ausblenden", 0.0f, 0.0f, 0.0f, 0.0f, cast(float[4])initButtonFill, cast(float[4])initButtonBorder, cast(float[4])initButtonText);
        initSettingsButton.onClick = &toggleSettingsWindow;
        initTestButton = new UiButton("Layout-Testfenster öffnen", 0.0f, 0.0f, 0.0f, 0.0f, cast(float[4])initButtonFill, cast(float[4])initButtonBorder, cast(float[4])initButtonText);
        initTestButton.onClick = &spawnLayoutTestWindow;

        initContent.add(initHelpButton);
        initContent.add(new UiSpacer(0.0f, sectionSpacing));
        initContent.add(initStatusButton);
        initContent.add(new UiSpacer(0.0f, sectionSpacing));
        initContent.add(initSettingsButton);
        initContent.add(new UiSpacer(0.0f, sectionSpacing));
        initContent.add(initTestButton);
        initWindow.add(initContent);
        initWindow.onClose = &requestQuit;
        initWindow.onHeaderDragStart = (cursorX, cursorY) { beginWindowDrag(initWindow, cursorX, cursorY); };
        initWindow.onHeaderDragMove = (cursorX, cursorY) { updateWindowDrag(cursorX, cursorY); };
        initWindow.onHeaderDragEnd = () { endWindowInteraction(); };
        initWindow.onResizeStart = (handle) { beginWindowResize(initWindow, handle); };
        initWindow.onResizeMove = (handle, cursorX, cursorY) { updateWindowResize(cursorX, cursorY); };
        initWindow.onResizeEnd = (handle) { endWindowInteraction(); };
    }

    void buildHelpWindow()
    {
        helpWindow = new UiWindow("Hilfe", windowMargin, windowMargin + initHeight + windowMargin, helpWidth, helpHeight, cast(float[4])helpBodyColor, cast(float[4])helpHeaderColor, cast(float[4])helpTitleColor, true, true, true, 14.0f, 12.0f, 14.0f, 12.0f);

        helpContent = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, contentSpacing);
        helpTitleLabel = new UiLabel("Fenster-Test-Shell", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpAccentColor);
        helpIntroLabel = new UiLabel("Das Init-Fenster öffnet und versteckt die sekundären Bereiche.", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpTextColor);
        helpLayoutLabel = new UiLabel("Neue Testfenster werden pro Klick erzeugt und können verschoben oder skaliert werden.", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpTextColor);
        helpCloseLabel = new UiLabel("Schließen-Schaltflächen verbergen nur das Fenster, zu dem sie gehören.", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpTextColor);

        helpContent.add(helpTitleLabel);
        helpContent.add(helpIntroLabel);
        helpContent.add(helpLayoutLabel);
        helpContent.add(helpCloseLabel);
        helpWindow.add(helpContent);
        helpWindow.visible = false;
        helpWindow.onClose = ()
        {
            helpWindow.visible = false;
            logLine("UiWindow close: Hilfe");
        };
        helpWindow.onHeaderDragStart = (cursorX, cursorY) { beginWindowDrag(helpWindow, cursorX, cursorY); };
        helpWindow.onHeaderDragMove = (cursorX, cursorY) { updateWindowDrag(cursorX, cursorY); };
        helpWindow.onHeaderDragEnd = () { endWindowInteraction(); };
        helpWindow.onResizeStart = (handle) { beginWindowResize(helpWindow, handle); };
        helpWindow.onResizeMove = (handle, cursorX, cursorY) { updateWindowResize(cursorX, cursorY); };
        helpWindow.onResizeEnd = (handle) { endWindowInteraction(); };
    }

    void buildStatusWindow()
    {
        statusWindow = new UiWindow("Status", windowMargin, windowMargin, statusWidth, statusHeight, cast(float[4])statusBodyColor, cast(float[4])statusHeaderColor, cast(float[4])statusTitleColor, true, true, true, 14.0f, 12.0f, 14.0f, 12.0f);

        statusContent = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, contentSpacing);
        statusBuildLabel = new UiLabel("Build: pending", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])statusTextColor);
        statusFpsLabel = new UiLabel("FPS: pending", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])statusTextColor);
        statusSceneLabel = new UiLabel("Szene: pending", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])statusTextColor);
        statusModeLabel = new UiLabel("Modus: pending", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])statusTextColor);
        statusViewportLabel = new UiLabel("Viewport: pending", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])statusAccentColor);

        statusContent.add(statusBuildLabel);
        statusContent.add(statusFpsLabel);
        statusContent.add(statusSceneLabel);
        statusContent.add(statusModeLabel);
        statusContent.add(statusViewportLabel);
        statusWindow.add(statusContent);
        statusWindow.visible = false;
        statusWindow.onClose = ()
        {
            statusWindow.visible = false;
            logLine("UiWindow close: Status");
        };
        statusWindow.onHeaderDragStart = (cursorX, cursorY) { beginWindowDrag(statusWindow, cursorX, cursorY); };
        statusWindow.onHeaderDragMove = (cursorX, cursorY) { updateWindowDrag(cursorX, cursorY); };
        statusWindow.onHeaderDragEnd = () { endWindowInteraction(); };
        statusWindow.onResizeStart = (handle) { beginWindowResize(statusWindow, handle); };
        statusWindow.onResizeMove = (handle, cursorX, cursorY) { updateWindowResize(cursorX, cursorY); };
        statusWindow.onResizeEnd = (handle) { endWindowInteraction(); };
    }

    void buildSettingsWindow()
    {
        settingsWindow = new UiWindow("Einstellungen", windowMargin, windowMargin, settingsWidth, settingsHeight, cast(float[4])settingsBodyColor, cast(float[4])settingsHeaderColor, cast(float[4])settingsTitleColor, true, true, true, 14.0f, 12.0f, 14.0f, 12.0f);

        settingsContent = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, contentSpacing);
        settingsTitleLabel = new UiLabel("Einstellungsfenster", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])settingsAccentColor);
        settingsIntroLabel = new UiLabel("Dieses Fenster ist für künftige Werkzeuge und Konfigurationsoptionen reserviert.", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])settingsTextColor);
        settingsProfileLabel = new UiLabel("Aktuelles Profil: Standard-Demoeinstellungen.", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])settingsTextColor);
        settingsPreviewLabel = new UiLabel("Nutze das Init-Fenster, um bei Bedarf weitere Testfenster zu öffnen.", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])settingsTextColor);

        settingsContent.add(settingsTitleLabel);
        settingsContent.add(settingsIntroLabel);
        settingsContent.add(settingsProfileLabel);
        settingsContent.add(settingsPreviewLabel);
        settingsWindow.add(settingsContent);
        settingsWindow.visible = false;
        settingsWindow.onClose = ()
        {
            settingsWindow.visible = false;
            logLine("UiWindow close: Einstellungen");
        };
        settingsWindow.onHeaderDragStart = (cursorX, cursorY) { beginWindowDrag(settingsWindow, cursorX, cursorY); };
        settingsWindow.onHeaderDragMove = (cursorX, cursorY) { updateWindowDrag(cursorX, cursorY); };
        settingsWindow.onHeaderDragEnd = () { endWindowInteraction(); };
        settingsWindow.onResizeStart = (handle) { beginWindowResize(settingsWindow, handle); };
        settingsWindow.onResizeMove = (handle, cursorX, cursorY) { updateWindowResize(cursorX, cursorY); };
        settingsWindow.onResizeEnd = (handle) { endWindowInteraction(); };
    }

    void updateStatusText(float fps, string currentShapeName, string currentRenderModeName, string buildVersion)
    {
        statusBuildLabel.text = format("Build: %s", buildVersion);
        statusFpsLabel.text = format("FPS: %.1f", fps);
        statusSceneLabel.text = format("Szene: %s", currentShapeName);
        statusModeLabel.text = format("Modus: %s", currentRenderModeName);
        statusViewportLabel.text = format("Viewport: %.0f x %.0f", viewportWidth, viewportHeight);
        helpIntroLabel.text = format("Geöffnete Fenster: %u", cast(uint)testWindows.length);
        settingsProfileLabel.text = format("Aktuelles Profil: %s", settingsDraft.display.windowMode);
    }

    void ensureWindowLayout()
    {
        if (viewportWidth <= 0.0f || viewportHeight <= 0.0f)
            return;

        layoutAllWindows();
        anchorWindows();
        clampWindowsToViewport();
    }

    void layoutAllWindows()
    {
        if (fontAtlases.length == 0)
            return;

        layoutContext = buildLayoutContext(fontAtlases);
        initWindow.layoutWindow(layoutContext);
        helpWindow.layoutWindow(layoutContext);
        statusWindow.layoutWindow(layoutContext);
        settingsWindow.layoutWindow(layoutContext);
        foreach (demoWindow; testWindows)
            demoWindow.layout(layoutContext);
    }

    void anchorWindows()
    {
        if (!initAnchored)
        {
            initWindow.x = windowMargin;
            initWindow.y = windowMargin;
            initAnchored = true;
        }

        if (!helpAnchored)
        {
            helpWindow.x = windowMargin;
            helpWindow.y = initWindow.y + initWindow.height + windowMargin;
            helpAnchored = true;
        }

        if (!statusAnchored)
        {
            statusWindow.x = viewportWidth > statusWindow.width ? viewportWidth - statusWindow.width - windowMargin : windowMargin;
            statusWindow.y = windowMargin;
            statusAnchored = true;
        }

        if (!settingsAnchored)
        {
            settingsWindow.x = viewportWidth > settingsWindow.width ? viewportWidth - settingsWindow.width - windowMargin : windowMargin;
            settingsWindow.y = viewportHeight > settingsWindow.height ? viewportHeight - settingsWindow.height - windowMargin : windowMargin;
            settingsAnchored = true;
        }

        foreach (index, demoWindow; testWindows)
        {
            const offset = windowMargin + cast(float)index * 22.0f;
            if (demoWindow.window.x <= 0.0f && demoWindow.window.y <= 0.0f)
            {
                demoWindow.window.x = max(windowMargin * 2.0f + offset, windowMargin);
                demoWindow.window.y = max(windowMargin * 2.0f + offset, windowMargin);
            }
        }
    }

    void clampWindowsToViewport()
    {
        clampWindowToViewport(initWindow);
        clampWindowToViewport(helpWindow);
        clampWindowToViewport(statusWindow);
        clampWindowToViewport(settingsWindow);
        foreach (demoWindow; testWindows)
            clampWindowToViewport(demoWindow.window);
    }

    void clampWindowToViewport(UiWindow window)
    {
        if (window is null)
            return;

        const maximumLeft = viewportWidth > window.width ? viewportWidth - window.width : 0.0f;
        const maximumTop = viewportHeight > window.height ? viewportHeight - window.height : 0.0f;
        window.x = clampFloat(window.x, 0.0f, maximumLeft);
        window.y = clampFloat(window.y, 0.0f, maximumTop);
    }

    void spawnLayoutTestWindow()
    {
        LayoutDemoWindow demoWindow = buildLayoutDemoWindow(nextTestWindowSerial++);
        const cascadeIndex = cast(float)(nextTestWindowSerial - 2);
        demoWindow.window.x += cascadeIndex * 28.0f;
        demoWindow.window.y += cascadeIndex * 24.0f;
        autoSizeWindow(demoWindow.window, demoWindow.content, windowContentPaddingX, windowContentPaddingY, windowContentPaddingX, windowContentPaddingY, testWindowWidth, testWindowHeight);
        demoWindow.window.onClose = ()
        {
            demoWindow.window.visible = false;
            removeLayoutDemoWindow(demoWindow);
            logLine("UiWindow close: ", demoWindow.window.title);
        };
        demoWindow.window.onHeaderDragStart = (cursorX, cursorY) { beginWindowDrag(demoWindow.window, cursorX, cursorY); };
        demoWindow.window.onHeaderDragMove = (cursorX, cursorY) { updateWindowDrag(cursorX, cursorY); };
        demoWindow.window.onHeaderDragEnd = () { endWindowInteraction(); };
        demoWindow.window.onResizeStart = (handle) { beginWindowResize(demoWindow.window, handle); };
        demoWindow.window.onResizeMove = (handle, cursorX, cursorY) { updateWindowResize(cursorX, cursorY); };
        demoWindow.window.onResizeEnd = (handle) { endWindowInteraction(); };
        testWindows ~= demoWindow;
        if (viewportWidth > 0.0f && viewportHeight > 0.0f)
            ensureWindowLayout();
        logLine("UiWindow spawn: ", demoWindow.window.title);
    }

    void removeLayoutDemoWindow(LayoutDemoWindow demoWindow)
    {
        if (demoWindow is null)
            return;

        if (activeDragWindow is demoWindow.window || activeResizeWindow is demoWindow.window)
            endWindowInteraction();

        for (size_t index = 0; index < testWindows.length; ++index)
        {
            if (testWindows[index] is demoWindow)
            {
                testWindows = testWindows[0 .. index] ~ testWindows[index + 1 .. $];
                break;
            }
        }
    }
}

@("UiScreen spawns and toggles the rebuilt windows")
unittest
{
    UiScreen screen = new UiScreen();
    screen.initialize([]);

    assert(screen.containsPointer(20.0f, 20.0f));
    screen.toggleSettingsWindow();
    assert(screen.settingsWindow.visible);
    screen.toggleSettingsWindow();
    assert(!screen.settingsWindow.visible);
    screen.spawnLayoutTestWindow();
    assert(screen.windowsInFrontToBack().length >= 5);
}
