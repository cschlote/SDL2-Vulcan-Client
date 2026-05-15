/** Builds the demo application's retained UI and overlay geometry.
 *
 * Organizes the demo window stack, drag state, and per-window draw ranges that
 * keep the overlay geometry grouped by window during rendering. The concrete
 * demo UI is built here; reusable widget behavior belongs in source/vulkan/ui/.
 *
 * See_Also:
 *   source/vulkan/ui/
 *   source/vulkan/engine/renderer.d
 *   docs/demo-ui-plan.md
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 *
 * Layout test helpers below are demo-only widgets used to exercise the retained
 * layout engine.
 */
module demo.demo_ui;

import std.format : format;
import std.algorithm : max;
import std.conv : ConvException, to;

import demo.demo_settings : DemoSettings;
import vulkan.font.font_legacy : FontAtlas;
import vulkan.engine.pipeline : Vertex;
import vulkan.ui.ui_event : UiResizeHandle;
import vulkan.ui.ui_context : UiRenderContext, UiTextStyle;
import vulkan.ui.ui_button : UiButton;
import vulkan.ui.ui_controls : UiDropdown, UiSlider, UiTextField, UiToggle;
import vulkan.ui.ui_label : UiLabel;
import vulkan.ui.ui_layout : UiHBox, UiSpacer, UiVBox;
import vulkan.ui.ui_layout_context : UiLayoutContext;
import vulkan.ui.ui_layout_context : UiLayoutSize;
import vulkan.ui.ui_screen : UiScreen;
import vulkan.ui.ui_window : UiWindow;
import vulkan.ui.ui_widget : UiWidget;
import vulkan.ui.ui_widget_helpers : appendSurfaceFrame;
import logging : logLine;

/** Describes one contiguous draw block inside the overlay buffers.
 *
 * Each range maps one logical window to a contiguous set of panel and text
 * vertices so the renderer can preserve the intended stacking order.
 */
struct UiWindowDrawRange
{
    /** Start index for panel vertices. */
    uint panelsStart;
    /** Vertex count for panel geometry. */
    uint panelsCount;
    /** Start indices for text vertices, indexed by UiTextStyle. */
    uint[7] textStarts;
    /** Vertex counts for text geometry, indexed by UiTextStyle. */
    uint[7] textCounts;
}

/** Holds the panel and text geometry for the UI overlay.
 *
 * The renderer uploads each vertex list independently and uses the draw ranges
 * to emit one logical window at a time.
 */
struct UiOverlayGeometry
{
    /** Window body and header quads. */
    Vertex[] panels;
    /** Text quads indexed by UiTextStyle. */
    Vertex[][7] textLayers;
    /** Draw ranges that keep each window's render calls contiguous. */
    UiWindowDrawRange[] windows;
}

private final class LayoutDemoProbeBox : UiWidget
{
    private float[4] fillColor;
    private float[4] borderColor;

    this(float width, float height, float[4] fillColor, float[4] borderColor)
    {
        super(0.0f, 0.0f, width, height);
        this.fillColor = fillColor;
        this.borderColor = borderColor;
    }

    override UiLayoutSize measureSelf(ref UiLayoutContext context)
    {
        setLayoutHint(preferredWidth, preferredHeight, preferredWidth, preferredHeight, preferredWidth, preferredHeight, 0.0f, 0.0f);
        return UiLayoutSize(preferredWidth, preferredHeight);
    }

    override void renderSelf(ref UiRenderContext context)
    {
        appendSurfaceFrame(context, 0.0f, 0.0f, width, height, fillColor, borderColor, context.depthBase);
    }
}

/** Builds a retained layout demo window that can be spawned repeatedly. */
final class LayoutDemoWindow
{
    UiWindow window;
    UiVBox content;

    this(uint serial, void delegate() onClose = null, void delegate(float, float) onHeaderDragStart = null, void delegate(float, float) onHeaderDragMove = null, void delegate() onHeaderDragEnd = null, void delegate(UiResizeHandle) onResizeStart = null, void delegate(UiResizeHandle, float, float) onResizeMove = null, void delegate(UiResizeHandle) onResizeEnd = null)
    {
        const windowTitle = format("Widget Demo #%u", serial);
        window = new UiWindow(windowTitle, 36.0f, 36.0f, 420.0f, 280.0f, [0.10f, 0.12f, 0.16f, 0.95f], [0.14f, 0.16f, 0.20f, 0.98f], [1.00f, 0.98f, 0.82f, 1.00f], true, true, true, 14.0f, 12.0f, 14.0f, 12.0f);

        content = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, 10.0f);
        auto topRow = new UiHBox(0.0f, 0.0f, 0.0f, 0.0f, 10.0f);
        topRow.setLayoutHint(0.0f, 0.0f, 0.0f, 0.0f, float.max, float.max, 1.0f, 1.0f);
        topRow.add(new LayoutDemoProbeBox(88.0f, 42.0f, [0.17f, 0.20f, 0.28f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f]));
        topRow.add(new LayoutDemoProbeBox(120.0f, 58.0f, [0.14f, 0.24f, 0.20f, 0.96f], [0.34f, 0.82f, 0.46f, 1.00f]));
        topRow.add(new LayoutDemoProbeBox(66.0f, 74.0f, [0.24f, 0.16f, 0.20f, 0.96f], [0.92f, 0.46f, 0.46f, 1.00f]));

        auto middleRow = new UiHBox(0.0f, 0.0f, 0.0f, 0.0f, 10.0f);
        middleRow.setLayoutHint(0.0f, 0.0f, 0.0f, 0.0f, float.max, float.max, 1.0f, 1.0f);
        auto middleColumn = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, 10.0f);
        middleColumn.setLayoutHint(0.0f, 0.0f, 0.0f, 0.0f, float.max, float.max, 1.0f, 1.0f);
        middleColumn.add(new LayoutDemoProbeBox(152.0f, 30.0f, [0.18f, 0.18f, 0.18f, 0.96f], [0.82f, 0.72f, 0.28f, 1.00f]));
        middleColumn.add(new LayoutDemoProbeBox(152.0f, 52.0f, [0.17f, 0.20f, 0.28f, 0.96f], [0.34f, 0.82f, 0.46f, 1.00f]));
        middleRow.add(middleColumn);
        middleRow.add(new LayoutDemoProbeBox(126.0f, 92.0f, [0.14f, 0.24f, 0.20f, 0.96f], [0.92f, 0.46f, 0.46f, 1.00f]));

        auto bottomRow = new UiHBox(0.0f, 0.0f, 0.0f, 0.0f, 10.0f);
        bottomRow.setLayoutHint(0.0f, 0.0f, 0.0f, 0.0f, float.max, float.max, 1.0f, 1.0f);
        bottomRow.add(new LayoutDemoProbeBox(72.0f, 40.0f, [0.24f, 0.16f, 0.20f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f]));
        bottomRow.add(new LayoutDemoProbeBox(164.0f, 40.0f, [0.18f, 0.18f, 0.18f, 0.96f], [0.34f, 0.82f, 0.46f, 1.00f]));
        bottomRow.add(new LayoutDemoProbeBox(92.0f, 40.0f, [0.17f, 0.20f, 0.28f, 0.96f], [0.82f, 0.72f, 0.28f, 1.00f]));

        content.add(new UiSpacer(12.0f, 6.0f));
        content.add(topRow);
        content.add(new UiSpacer(12.0f, 6.0f));
        content.add(middleRow);
        content.add(new UiSpacer(12.0f, 6.0f));
        content.add(bottomRow);
        content.setLayoutHint(0.0f, 0.0f, 0.0f, 0.0f, float.max, float.max, 1.0f, 1.0f);

        UiLayoutContext layoutContext;
        content.layout(layoutContext);
        const minimumWidth = content.width + 34.0f;
        const minimumHeight = content.height + window.headerHeight + 30.0f;
        window.minimumWidth = minimumWidth;
        window.minimumHeight = minimumHeight;
        if (window.width < minimumWidth)
            window.width = minimumWidth;
        if (window.height < minimumHeight)
            window.height = minimumHeight;

        window.add(content);
        window.visible = true;
        window.onClose = onClose;
        window.onHeaderDragStart = onHeaderDragStart;
        window.onHeaderDragMove = onHeaderDragMove;
        window.onHeaderDragEnd = onHeaderDragEnd;
        window.onResizeStart = onResizeStart;
        window.onResizeMove = onResizeMove;
        window.onResizeEnd = onResizeEnd;
    }

    void layout(ref UiLayoutContext context)
    {
        window.layoutWindow(context);
    }
}

/** Creates a new retained layout demo window. */
LayoutDemoWindow buildLayoutDemoWindow(uint serial, void delegate() onClose = null, void delegate(float, float) onHeaderDragStart = null, void delegate(float, float) onHeaderDragMove = null, void delegate() onHeaderDragEnd = null, void delegate(UiResizeHandle) onResizeStart = null, void delegate(UiResizeHandle, float, float) onResizeMove = null, void delegate(UiResizeHandle) onResizeEnd = null)
{
    return new LayoutDemoWindow(serial, onClose, onHeaderDragStart, onHeaderDragMove, onHeaderDragEnd, onResizeStart, onResizeMove, onResizeEnd);
}


private enum float windowMargin = 10.0f;
private enum float initWidth = 160.0f;
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
private enum float overlayWindowDepth = 0.10f;

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

final class DemoUiScreen : UiScreen
{
    DemoSettings settingsDraft;
    bool sceneMouseDragging;
    void delegate() onApplySettings;
    void delegate() onSaveSettings;

    private UiWindow initWindow;
    private UiWindow helpWindow;
    private UiWindow statusWindow;
    private UiWindow settingsWindow;
    private LayoutDemoWindow[] testWindows;
    private UiVBox initContent;
    private UiVBox helpContent;
    private UiVBox statusContent;
    private UiVBox settingsContent;
    private UiVBox settingsBody;
    private UiHBox settingsActionRow;
    private UiButton initHelpButton;
    private UiButton initStatusButton;
    private UiButton initSettingsButton;
    private UiButton initTestButton;

    private UiLabel helpTitleLabel;
    private UiLabel helpIntroLabel;
    private UiLabel helpLayoutLabel;
    private UiLabel helpCloseLabel;
    private UiLabel helpDebugLegendTitleLabel;
    private UiLabel helpDebugLegendWindowLabel;
    private UiLabel helpDebugLegendSurfaceLabel;
    private UiLabel helpDebugLegendVBoxLabel;
    private UiLabel helpDebugLegendHBoxLabel;
    private UiLabel helpDebugLegendGridLabel;
    private UiLabel helpDebugLegendSpacerLabel;
    private UiLabel helpDebugLegendWidgetLabel;

    private UiLabel statusBuildLabel;
    private UiLabel statusFpsLabel;
    private UiLabel statusSceneLabel;
    private UiLabel statusModeLabel;
    private UiLabel statusViewportLabel;

    private UiLabel settingsTitleLabel;
    private UiLabel settingsIntroLabel;
    private UiLabel settingsProfileLabel;
    private UiDropdown settingsWindowModeDropdown;
    private UiTextField settingsWidthField;
    private UiTextField settingsHeightField;
    private UiToggle settingsVsyncToggle;
    private UiSlider settingsScaleSlider;
    private UiDropdown settingsThemeDropdown;
    private UiToggle settingsCompactToggle;
    private UiButton settingsApplyButton;
    private UiButton settingsSaveButton;

    private bool initAnchored;
    private bool helpAnchored;
    private bool statusAnchored;
    private bool settingsAnchored;

    private uint nextTestWindowSerial = 1;

    bool quitRequested;

    override void onInitialize()
    {
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
    }

    void syncViewport(float extentWidth, float extentHeight, float fps, string currentShapeName, string currentRenderModeName, string buildVersion)
    {
        super.syncViewport(extentWidth, extentHeight);
        updateStatusText(fps, currentShapeName, currentRenderModeName, buildVersion);
        ensureWindowLayout();
    }

    UiOverlayGeometry buildOverlayVertices(float extentWidth, float extentHeight, float fps, string currentShapeName, string currentRenderModeName, string buildVersion, const(FontAtlas)[] liveFonts, bool debugWidgetBounds = false)
    {
        syncViewport(extentWidth, extentHeight, fps, currentShapeName, currentRenderModeName, buildVersion);

        UiOverlayGeometry geometry;
        geometry.panels = [];
        foreach (layerIndex; 0 .. geometry.textLayers.length)
            geometry.textLayers[layerIndex] = [];

        UiWindowDrawRange[] drawRanges;
        UiRenderContext context = UiRenderContext.init;
        context.extentWidth = extentWidth;
        context.extentHeight = extentHeight;
        context.originX = 0.0f;
        context.originY = 0.0f;
        context.depthBase = 0.10f;
        context.debugWidgetBounds = debugWidgetBounds;
        foreach (index; 0 .. context.fonts.length)
            context.fonts[index] = index < liveFonts.length ? &liveFonts[index] : null;
        context.panels = &geometry.panels;
        foreach (index; 0 .. context.textLayers.length)
            context.textLayers[index] = &geometry.textLayers[index];

        foreach (window; windowsInFrontToBack())
        {
            if (!window.visible)
                continue;

            UiWindowDrawRange range;
            range.panelsStart = cast(uint)geometry.panels.length;
            foreach (layerIndex; 0 .. geometry.textLayers.length)
                range.textStarts[layerIndex] = cast(uint)geometry.textLayers[layerIndex].length;

            context.depthBase = overlayWindowDepth;
            window.render(context);

            range.panelsCount = cast(uint)(geometry.panels.length - range.panelsStart);
            foreach (layerIndex; 0 .. geometry.textLayers.length)
                range.textCounts[layerIndex] = cast(uint)(geometry.textLayers[layerIndex].length - range.textStarts[layerIndex]);

            drawRanges ~= range;
        }

        geometry.windows = drawRanges;
        return geometry;
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

    void openSettingsDialog(const(DemoSettings)* liveSettings)
    {
        if (liveSettings !is null)
            settingsDraft = *liveSettings;
        refreshSettingsControls();
        if (!settingsWindow.visible)
            toggleSettingsWindow();
    }

    void toggleSettingsDialog(const(DemoSettings)* liveSettings)
    {
        if (liveSettings !is null)
            settingsDraft = *liveSettings;
        refreshSettingsControls();
        toggleSettingsWindow();
    }

    void setSettingsDraft(const(DemoSettings)* liveSettings)
    {
        if (liveSettings is null)
            return;

        settingsDraft = *liveSettings;
        refreshSettingsControls();
    }

    void updateWindowState()
    {
        initWindow.visible = true;
        helpWindow.visible = false;
        statusWindow.visible = false;
        settingsWindow.visible = false;
    }

    void buildInitWindow()
    {
        initWindow = new UiWindow("Demo Control", windowMargin, windowMargin, initWidth, initHeight, cast(float[4])initBodyColor, cast(float[4])initHeaderColor, cast(float[4])initTitleColor, true, true, true, 14.0f, 12.0f, 14.0f, 12.0f);

        initContent = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, contentSpacing);
        initHelpButton = new UiButton("Toggle Controls / Log", 0.0f, 0.0f, 0.0f, 0.0f, cast(float[4])initButtonFill, cast(float[4])initButtonBorder, cast(float[4])initButtonText);
        initHelpButton.onClick = &toggleHelpWindow;
        initStatusButton = new UiButton("Toggle Status", 0.0f, 0.0f, 0.0f, 0.0f, cast(float[4])initButtonFill, cast(float[4])initButtonBorder, cast(float[4])initButtonText);
        initStatusButton.onClick = &toggleStatusWindow;
        initSettingsButton = new UiButton("Open Settings", 0.0f, 0.0f, 0.0f, 0.0f, cast(float[4])initButtonFill, cast(float[4])initButtonBorder, cast(float[4])initButtonText);
        initSettingsButton.onClick = () { toggleSettingsDialog(null); };
        initTestButton = new UiButton("Open Widget Demo", 0.0f, 0.0f, 0.0f, 0.0f, cast(float[4])initButtonFill, cast(float[4])initButtonBorder, cast(float[4])initButtonText);
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
        registerWindowInteractionHandlers(initWindow);
        addWindow(initWindow);
    }

    void buildHelpWindow()
    {
        helpWindow = new UiWindow("Controls / Log", windowMargin, windowMargin + initHeight + windowMargin, helpWidth, helpHeight, cast(float[4])helpBodyColor, cast(float[4])helpHeaderColor, cast(float[4])helpTitleColor, true, true, true, 14.0f, 12.0f, 14.0f, 12.0f);

        helpContent = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, contentSpacing);
        helpTitleLabel = new UiLabel("Keyboard and mouse controls", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpAccentColor);
        helpIntroLabel = new UiLabel("Open windows: 0", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpTextColor);
        helpLayoutLabel = new UiLabel("Arrow keys rotate, Shift accelerates, mouse drag rotates outside UI.", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpTextColor);
        helpCloseLabel = new UiLabel("F/T/W/H switch render modes, D toggles UI bounds, Esc quits.", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpTextColor);
        helpDebugLegendTitleLabel = new UiLabel("Debug bounds colors:", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpAccentColor);
        helpDebugLegendWindowLabel = new UiLabel("Orange: UiWindow", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpTextColor);
        helpDebugLegendSurfaceLabel = new UiLabel("Cyan: UiSurfaceBox / content root", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpTextColor);
        helpDebugLegendVBoxLabel = new UiLabel("Green: UiVBox", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpTextColor);
        helpDebugLegendHBoxLabel = new UiLabel("Blue: UiHBox", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpTextColor);
        helpDebugLegendGridLabel = new UiLabel("Purple: UiGrid", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpTextColor);
        helpDebugLegendSpacerLabel = new UiLabel("Yellow: UiSpacer", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpTextColor);
        helpDebugLegendWidgetLabel = new UiLabel("Red: basic widgets and controls", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpTextColor);

        helpContent.add(helpTitleLabel);
        helpContent.add(helpIntroLabel);
        helpContent.add(helpLayoutLabel);
        helpContent.add(helpCloseLabel);
        helpContent.add(new UiSpacer(0.0f, sectionSpacing));
        helpContent.add(helpDebugLegendTitleLabel);
        helpContent.add(helpDebugLegendWindowLabel);
        helpContent.add(helpDebugLegendSurfaceLabel);
        helpContent.add(helpDebugLegendVBoxLabel);
        helpContent.add(helpDebugLegendHBoxLabel);
        helpContent.add(helpDebugLegendGridLabel);
        helpContent.add(helpDebugLegendSpacerLabel);
        helpContent.add(helpDebugLegendWidgetLabel);
        helpWindow.add(helpContent);
        helpWindow.visible = false;
        helpWindow.onClose = ()
        {
            helpWindow.visible = false;
            logLine("UiWindow close: Controls / Log");
        };
        registerWindowInteractionHandlers(helpWindow);
        addWindow(helpWindow);
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
        registerWindowInteractionHandlers(statusWindow);
        addWindow(statusWindow);
    }

    void buildSettingsWindow()
    {
        settingsWindow = new UiWindow("Settings", windowMargin, windowMargin, settingsWidth, settingsHeight, cast(float[4])settingsBodyColor, cast(float[4])settingsHeaderColor, cast(float[4])settingsTitleColor, true, true, true, 14.0f, 12.0f, 14.0f, 12.0f);

        settingsContent = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, contentSpacing);
        settingsTitleLabel = new UiLabel("Runtime configuration", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])settingsAccentColor);
        settingsIntroLabel = new UiLabel("Apply changes this run. Save writes the config file.", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])settingsTextColor);
        settingsProfileLabel = new UiLabel("Profile: default", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])settingsTextColor);
        settingsWindowModeDropdown = new UiDropdown("Window Mode", ["windowed", "fullscreen", "borderless"], 0, 0.0f, 0.0f, 220.0f, 28.0f);
        settingsWidthField = new UiTextField("", "Width", 0.0f, 0.0f, 104.0f, 28.0f);
        settingsHeightField = new UiTextField("", "Height", 0.0f, 0.0f, 104.0f, 28.0f);
        settingsVsyncToggle = new UiToggle("VSync", false, 0.0f, 0.0f, 220.0f, 28.0f);
        settingsScaleSlider = new UiSlider("UI Scale", 0.50f, 2.00f, 1.00f, 0.0f, 0.0f, 220.0f, 32.0f);
        settingsThemeDropdown = new UiDropdown("Theme", ["midnight", "classic", "contrast"], 0, 0.0f, 0.0f, 220.0f, 28.0f);
        settingsCompactToggle = new UiToggle("Compact Windows", false, 0.0f, 0.0f, 220.0f, 28.0f);
        settingsApplyButton = new UiButton("Apply", 0.0f, 0.0f, 104.0f, 30.0f, cast(float[4])initButtonFill, cast(float[4])initButtonBorder, cast(float[4])initButtonText);
        settingsSaveButton = new UiButton("Save", 0.0f, 0.0f, 104.0f, 30.0f, cast(float[4])initButtonFill, cast(float[4])initButtonBorder, cast(float[4])initButtonText);

        settingsWindowModeDropdown.onChanged = (index, value) { settingsDraft.display.windowMode = value; updateSettingsSummary(); };
        settingsWidthField.onChanged = (value) { settingsDraft.display.windowWidth = parseUintSetting(value, settingsDraft.display.windowWidth); updateSettingsSummary(); };
        settingsHeightField.onChanged = (value) { settingsDraft.display.windowHeight = parseUintSetting(value, settingsDraft.display.windowHeight); updateSettingsSummary(); };
        settingsVsyncToggle.onChanged = (value) { settingsDraft.display.vsync = value; updateSettingsSummary(); };
        settingsScaleSlider.onChanged = (value) { settingsDraft.display.scale = value; updateSettingsSummary(); };
        settingsThemeDropdown.onChanged = (index, value) { settingsDraft.ui.theme = value; updateSettingsSummary(); };
        settingsCompactToggle.onChanged = (value) { settingsDraft.ui.compactWindows = value; updateSettingsSummary(); };
        settingsApplyButton.onClick = &applySettingsFromDialog;
        settingsSaveButton.onClick = &saveSettingsFromDialog;

        auto sizeRow = new UiHBox(0.0f, 0.0f, 0.0f, 0.0f, contentSpacing);
        sizeRow.add(settingsWidthField);
        sizeRow.add(settingsHeightField);

        settingsBody = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, contentSpacing);
        settingsBody.setLayoutHint(0.0f, 0.0f, 0.0f, 0.0f, float.max, float.max, 1.0f, 1.0f);
        settingsBody.add(settingsTitleLabel);
        settingsBody.add(settingsIntroLabel);
        settingsBody.add(settingsProfileLabel);
        settingsBody.add(settingsWindowModeDropdown);
        settingsBody.add(sizeRow);
        settingsBody.add(settingsVsyncToggle);
        settingsBody.add(settingsScaleSlider);
        settingsBody.add(settingsThemeDropdown);
        settingsBody.add(settingsCompactToggle);

        settingsActionRow = new UiHBox(0.0f, 0.0f, 0.0f, 0.0f, contentSpacing);
        settingsActionRow.add(settingsApplyButton);
        settingsActionRow.add(settingsSaveButton);

        settingsContent.add(settingsBody);
        settingsContent.add(settingsActionRow);
        settingsWindow.add(settingsContent);
        settingsWindow.visible = false;
        settingsWindow.onClose = ()
        {
            settingsWindow.visible = false;
            logLine("UiWindow close: Settings");
        };
        registerWindowInteractionHandlers(settingsWindow);
        addWindow(settingsWindow);
        refreshSettingsControls();
    }

    void refreshSettingsControls()
    {
        if (settingsWindowModeDropdown is null)
            return;

        settingsWindowModeDropdown.selectedIndex = optionIndex(settingsWindowModeDropdown.options, settingsDraft.display.windowMode);
        settingsWidthField.setText(format("%u", settingsDraft.display.windowWidth));
        settingsHeightField.setText(format("%u", settingsDraft.display.windowHeight));
        settingsVsyncToggle.checked = settingsDraft.display.vsync;
        settingsScaleSlider.value = settingsDraft.display.scale;
        settingsThemeDropdown.selectedIndex = optionIndex(settingsThemeDropdown.options, settingsDraft.ui.theme);
        settingsCompactToggle.checked = settingsDraft.ui.compactWindows;
        updateSettingsSummary();
    }

    void applySettingsFromDialog()
    {
        syncSettingsDraftFromControls();
        if (onApplySettings !is null)
            onApplySettings();
    }

    void saveSettingsFromDialog()
    {
        syncSettingsDraftFromControls();
        if (onSaveSettings !is null)
            onSaveSettings();
    }

    void syncSettingsDraftFromControls()
    {
        if (settingsWindowModeDropdown is null)
            return;

        settingsDraft.display.windowMode = settingsWindowModeDropdown.selectedText();
        settingsDraft.display.windowWidth = parseUintSetting(settingsWidthField.text, settingsDraft.display.windowWidth);
        settingsDraft.display.windowHeight = parseUintSetting(settingsHeightField.text, settingsDraft.display.windowHeight);
        settingsDraft.display.vsync = settingsVsyncToggle.checked;
        settingsDraft.display.scale = settingsScaleSlider.value;
        settingsDraft.ui.theme = settingsThemeDropdown.selectedText();
        settingsDraft.ui.compactWindows = settingsCompactToggle.checked;
        updateSettingsSummary();
    }

    void updateSettingsSummary()
    {
        if (settingsProfileLabel is null)
            return;

        settingsProfileLabel.text = format("Profil: %s, %ux%u, Theme %s", settingsDraft.display.windowMode, settingsDraft.display.windowWidth, settingsDraft.display.windowHeight, settingsDraft.ui.theme);
    }

    static size_t optionIndex(string[] options, string value)
    {
        foreach (index, option; options)
        {
            if (option == value)
                return index;
        }

        return 0;
    }

    static uint parseUintSetting(string value, uint fallback)
    {
        try
        {
            return to!uint(value);
        }
        catch (ConvException)
        {
            return fallback;
        }
        catch (Exception)
        {
            return fallback;
        }
    }

    void updateStatusText(float fps, string currentShapeName, string currentRenderModeName, string buildVersion)
    {
        statusBuildLabel.text = format("Build: %s", buildVersion);
        statusFpsLabel.text = format("FPS: %.1f", fps);
        statusSceneLabel.text = format("Szene: %s", currentShapeName);
        statusModeLabel.text = format("Modus: %s", currentRenderModeName);
        statusViewportLabel.text = format("Viewport: %.0f x %.0f", viewportWidth, viewportHeight);
        helpIntroLabel.text = format("Open widget demos: %u", cast(uint)testWindows.length);
        updateSettingsSummary();
    }

    override void anchorWindows()
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
        registerWindowInteractionHandlers(demoWindow.window);
        testWindows ~= demoWindow;
        addWindow(demoWindow.window);
        if (viewportWidth > 0.0f && viewportHeight > 0.0f)
        {
            ensureWindowLayout();
            placeWindowWithoutOverlap(demoWindow.window);
        }
        logLine("UiWindow spawn: ", demoWindow.window.title);
    }

    void removeLayoutDemoWindow(LayoutDemoWindow demoWindow)
    {
        if (demoWindow is null)
            return;

        for (size_t index = 0; index < testWindows.length; ++index)
        {
            if (testWindows[index] is demoWindow)
            {
                testWindows = testWindows[0 .. index] ~ testWindows[index + 1 .. $];
                break;
            }
        }

        removeWindow(demoWindow.window);
    }
}

@("DemoUiScreen spawns and toggles the rebuilt windows")
unittest
{
    DemoUiScreen screen = new DemoUiScreen();
    screen.initialize([]);

    assert(screen.containsPointer(20.0f, 20.0f));
    screen.toggleSettingsWindow();
    assert(screen.settingsWindow.visible);
    screen.toggleSettingsWindow();
    assert(!screen.settingsWindow.visible);
    screen.spawnLayoutTestWindow();
    assert(screen.windowsInFrontToBack().length >= 5);
}
