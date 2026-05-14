/** Builds the demo's HUD layout and overlay geometry.
 *
 * Organizes the window stack, drag state, and per-window draw ranges that keep
 * the overlay geometry grouped by window during rendering. The layout feeds
 * the retained widgets in source/vulkan/ui.d and the command-buffer
 * orchestration in source/vulkan/renderer.d.
 *
 * See_Also:
 *   source/vulkan/ui.d
 *   source/vulkan/renderer.d
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 *
 * Legacy helper block below is kept only until the old HUD geometry path is fully removed.
 */
module vulkan.ui_layer;

import std.format : format;
import std.algorithm : max, min;
import std.math : PI;

import demo_settings : DemoSettings;
import vulkan.font : FontAtlas;
import vulkan.pipeline : Vertex;
import vulkan.ui.ui_event : UiPointerEvent, UiPointerEventKind, UiResizeHandle;
import vulkan.ui.ui_context : UiRenderContext, UiTextStyle;
import vulkan.ui.ui_button : UiButton;
import vulkan.ui.ui_container : UiContainer;
import vulkan.ui.ui_label : UiLabel, UiTextBlock;
import vulkan.ui.ui_layout : UiHBox, UiSpacer, UiVBox;
import vulkan.ui.ui_window : UiWindow;
import logging : logLine;

/** Describes one HUD window rectangle in pixel coordinates.
 *
 * The renderer uses these rectangles to place the corner windows and the
 * draggable center window in native screen space.
 */
struct HudWindowRect
{
    /** Left edge in pixels. */
    float left;
    /** Top edge in pixels. */
    float top;
    /** Width in pixels. */
    float width;
    /** Height in pixels. */
    float height;
}

/** Tracks the draggable middle window and keeps it within the viewport.
 *
 * This state survives frame-to-frame so mouse dragging can continue smoothly
 * while the center window stays clamped to the swapchain extent.
 */
struct HudLayoutState
{
    /** Current left edge of the center window. */
    float middleLeft;
    /** Current top edge of the center window. */
    float middleTop;
    /** Current width of the center window. */
    float middleWidth;
    /** Current height of the center window. */
    float middleHeight;
    /** Minimum width required by the current center-window content. */
    float middleMinimumWidth;
    /** Minimum height required by the current center-window content. */
    float middleMinimumHeight;
    /** Whether the center window has been initialized once. */
    bool middleInitialized;
    /** Whether the status window is currently shown. */
    bool statusVisible = true;
    /** Whether the font sample window is currently shown. */
    bool sampleVisible = true;
    /** Whether the input help window is currently shown. */
    bool inputVisible = true;
    /** Whether the center window is currently shown. */
    bool centerVisible = true;
    /** Whether the settings dialog is currently shown. */
    bool settingsVisible;
    /** Current left edge of the settings dialog. */
    float settingsLeft;
    /** Current top edge of the settings dialog. */
    float settingsTop;
    /** Current width of the settings dialog. */
    float settingsWidth;
    /** Current height of the settings dialog. */
    float settingsHeight;
    /** Whether the settings dialog has been initialized once. */
    bool settingsInitialized;
    /** Whether the settings dialog is currently being dragged. */
    bool settingsDragging;
    /** Cursor offset captured when the settings drag starts. */
    float settingsDragOffsetX;
    /** Cursor offset captured when the settings drag starts. */
    float settingsDragOffsetY;
    /** Whether a drag is currently active. */
    bool middleDragging;
    /** Whether a resize is currently active. */
    bool middleResizing;
    /** Corner currently driving the resize gesture. */
    UiResizeHandle middleResizeHandle;
    /** Left edge captured when the resize starts. */
    float middleResizeStartLeft;
    /** Top edge captured when the resize starts. */
    float middleResizeStartTop;
    /** Width captured when the resize starts. */
    float middleResizeStartWidth;
    /** Height captured when the resize starts. */
    float middleResizeStartHeight;
    /** Cursor offset captured when the drag starts. */
    float dragOffsetX;
    /** Cursor offset captured when the drag starts. */
    float dragOffsetY;
}

/** Pixel layout for all HUD windows.
 *
 * The renderer keeps the status, modes, sample, input, and center windows in
 * separate rectangles so hit testing and drawing can stay deterministic.
 */
struct HudLayout
{
    /** Top-left status window. */
    HudWindowRect status;
    /** Top-right render-modes window. */
    HudWindowRect modes;
    /** Bottom-left font sample window. */
    HudWindowRect sample;
    /** Bottom-right input help window. */
    HudWindowRect input;
    /** Draggable center window. */
    HudWindowRect center;
}

/** Describes one contiguous draw block inside the overlay buffers.
 *
 * Each range maps one logical window to a contiguous set of panel and text
 * vertices so the renderer can preserve the intended stacking order.
 */
struct HudWindowDrawRange
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

/** Holds the panel and text geometry for the HUD overlay.
 *
 * The renderer uploads each vertex list independently and uses the draw ranges
 * to emit one logical window at a time.
 */
struct HudOverlayGeometry
{
    /** Window body and header quads. */
    Vertex[] panels;
    /** Text quads indexed by UiTextStyle. */
    Vertex[][7] textLayers;
    /** Draw ranges that keep each window's render calls contiguous. */
    HudWindowDrawRange[] windows;
}

/** Builds the HUD overlay geometry for the current frame.
 *
 * The output is the bridge between the retained widget tree and the renderer's
 * per-frame vertex buffers.
 *
 *
 * @param extentWidth = Swapchain width in pixels.
 * @param extentHeight = Swapchain height in pixels.
 * @param fps = Last measured frame rate.
 * @param yawAngle = Current yaw angle in radians.
 * @param pitchAngle = Current pitch angle in radians.
 * @param shapeName = Name of the active polyhedron.
 * @param renderModeName = Name of the active render mode.
 * @param smallFont = Font atlas used for 12 px body copy.
 * @param mediumFont = Font atlas used for 18 px labels and titles.
 * @param largeFont = Font atlas used for 24 px comparison samples.
 * @returns Panel and text vertex lists that can be uploaded to the GPU.
 */
HudOverlayGeometry buildHudOverlayVertices(
    float extentWidth,
    float extentHeight,
    float fps,
    float yawAngle,
    float pitchAngle,
    string shapeName,
    string renderModeName,
    string buildVersion,
    ref HudLayoutState layoutState,
    ref DemoSettings settingsDraft,
    string platformName,
    uint vulkanApiVersion,
    void delegate() onFlatColor,
    void delegate() onLitTextured,
    void delegate() onWireframe,
    void delegate() onHiddenLine,
    void delegate() onPreviousShape,
    void delegate() onNextShape,
    void delegate() onOpenSettings,
    void delegate() onApplySettings,
    const(FontAtlas)[] fontAtlases,
    ref const(FontAtlas) smallFont,
    ref const(FontAtlas) mediumFont,
    ref const(FontAtlas) largeFont)
{
    HudOverlayGeometry geometry;

    const layout = buildHudLayout(extentWidth, extentHeight, fps, yawAngle, pitchAngle, shapeName, renderModeName, layoutState, fontAtlases, smallFont, mediumFont, largeFont);
    UiWindow[] windows;
    if (layoutState.statusVisible)
        windows ~= buildStatusWindow(layout.status, layoutState, fps, yawAngle, pitchAngle, shapeName, renderModeName, buildVersion, platformName, vulkanApiVersion, smallFont, mediumFont);
    windows ~= buildModeWindow(
        layout.modes,
        smallFont,
        onFlatColor,
        onLitTextured,
        onWireframe,
        onHiddenLine,
        onPreviousShape,
        onNextShape,
        onOpenSettings,
        () { layoutState.statusVisible = !layoutState.statusVisible; },
        () { layoutState.sampleVisible = !layoutState.sampleVisible; },
        () { layoutState.inputVisible = !layoutState.inputVisible; },
        () { layoutState.centerVisible = !layoutState.centerVisible; });
    if (layoutState.sampleVisible)
        windows ~= buildSampleWindow(layout.sample, fontAtlases, smallFont, mediumFont, largeFont);
    if (layoutState.inputVisible)
        windows ~= buildInputWindow(layout.input, smallFont);
    windows ~= buildCenterWindow(layout.center, layoutState, extentWidth, extentHeight, smallFont, mediumFont);

    windows ~= buildSettingsWindow(buildSettingsRect(extentWidth, extentHeight, layoutState), layoutState, extentWidth, extentHeight, settingsDraft, onApplySettings, smallFont, mediumFont);

    foreach (index, window; windows)
    {
        Vertex[] windowPanels;
        Vertex[][7] windowTextLayers;

        UiRenderContext context = UiRenderContext.init;
        context.extentWidth = extentWidth;
        context.extentHeight = extentHeight;
        context.originX = 0.0f;
        context.originY = 0.0f;
        context.depthBase = 0.10f - cast(float)index * 0.02f;
        foreach (layerIndex; 0 .. context.fonts.length)
            context.fonts[layerIndex] = &fontAtlases[layerIndex];
        context.panels = &windowPanels;
        foreach (layerIndex; 0 .. windowTextLayers.length)
            context.textLayers[layerIndex] = &windowTextLayers[layerIndex];

        window.render(context);

        HudWindowDrawRange range;
        range.panelsStart = cast(uint)geometry.panels.length;
        range.panelsCount = cast(uint)windowPanels.length;
        foreach (layerIndex; 0 .. windowTextLayers.length)
        {
            range.textStarts[layerIndex] = cast(uint)geometry.textLayers[layerIndex].length;
            range.textCounts[layerIndex] = cast(uint)windowTextLayers[layerIndex].length;
        }
        geometry.windows ~= range;

        geometry.panels ~= windowPanels;
        foreach (layerIndex; 0 .. windowTextLayers.length)
            geometry.textLayers[layerIndex] ~= windowTextLayers[layerIndex];
    }

    return geometry;
}

/** Builds the pixel layout for all HUD windows.
 *
 * This layout is shared by hit testing, dragging, and rendering so the HUD
 * stays consistent across the input and draw paths.
 */
HudLayout buildHudLayout(float extentWidth, float extentHeight, float fps, float yawAngle, float pitchAngle, string shapeName, string renderModeName, ref HudLayoutState layoutState, const(FontAtlas)[] fontAtlases, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont, ref const(FontAtlas) largeFont)
{
    HudLayout layout;
    layout.status = buildStatusRect(extentWidth, extentHeight, fps, yawAngle, pitchAngle, shapeName, renderModeName, smallFont, mediumFont);
    layout.modes = buildModesRect(extentWidth, extentHeight, smallFont);
    layout.sample = buildSampleRect(extentWidth, extentHeight, fontAtlases);
    layout.input = buildInputRect(extentWidth, extentHeight, smallFont, mediumFont);
    layout.center = buildCenterRect(extentWidth, extentHeight, layoutState, smallFont, mediumFont);
    return layout;
}

private UiWindow buildStatusWindow(HudWindowRect rect, ref HudLayoutState layoutState, float fps, float yawAngle, float pitchAngle, string shapeName, string renderModeName, string buildVersion, string platformName, uint vulkanApiVersion, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont)
{
    const titleText = "STATUS";
    const platformText = format("PLATFORM: %s", platformName);
    const vulkanVersionText = format("VULKAN API: %u.%u.%u", cast(uint)(vulkanApiVersion >> 22), cast(uint)((vulkanApiVersion >> 12) & 0x3ff), cast(uint)(vulkanApiVersion & 0xfff));
    const buildText = format("BUILD: %s", buildVersion);
    const firstBodyWidth = textBlockWidth(smallFont, platformText);
    const secondBodyWidth = textBlockWidth(smallFont, vulkanVersionText);
    const thirdBodyWidth = textBlockWidth(mediumFont, format("FRAME RATE: %.0f FPS", fps));
    const fourthBodyWidth = textBlockWidth(smallFont, format("CAMERA YAW: %.1f DEGREES", yawAngle * 180.0f / cast(float)PI));
    const fifthBodyWidth = textBlockWidth(smallFont, format("CAMERA PITCH: %.1f DEGREES", pitchAngle * 180.0f / cast(float)PI));
    const sixthBodyWidth = textBlockWidth(smallFont, format("ACTIVE SHAPE: %s", shapeName));
    const seventhBodyWidth = textBlockWidth(smallFont, format("CURRENT MODE: %s", renderModeName));
    const contentWidth = max(max(max(max(max(max(firstBodyWidth, secondBodyWidth), max(thirdBodyWidth, fourthBodyWidth)), max(fifthBodyWidth, sixthBodyWidth)), seventhBodyWidth), textBlockWidth(smallFont, buildText)), textBlockWidth(smallFont, "MODEL / CAMERA / API / BUILD"));
    const titleWidth = textBlockWidth(mediumFont, titleText);
    const width = max(titleWidth + 20.0f, contentWidth + 24.0f);
    const smallTextHeight = textBlockHeight(smallFont);
    const mediumTextHeight = textBlockHeight(mediumFont);
    const contentBottom = max(max(max(max(max(max(smallTextHeight, 18.0f + smallTextHeight), 34.0f + smallTextHeight), 52.0f + mediumTextHeight), 76.0f + smallTextHeight), 98.0f + smallTextHeight), 120.0f + smallTextHeight);
    const height = 28.0f + contentBottom + 12.0f;
    auto window = new UiWindow(titleText, rect.left, rect.top, rect.width, rect.height, [0.10f, 0.12f, 0.16f, 0.96f], [0.14f, 0.16f, 0.20f, 0.96f], [1.00f, 0.98f, 0.82f, 1.00f], false, true, false);
    window.visible = layoutState.statusVisible;
    window.onClose = ()
    {
        logLine("UiWindow close: STATUS");
        layoutState.statusVisible = false;
    };
    auto content = new UiVBox(0.0f, 0.0f, max(rect.width - 28.0f, 0.0f), max(rect.height - 28.0f, 0.0f));
    content.add(new UiLabel(platformText, 0.0f, 0.0f, UiTextStyle.small, [0.72f, 0.96f, 1.00f, 1.00f], smallTextHeight));
    content.add(new UiSpacer(0.0f, 4.0f));
    content.add(new UiLabel(vulkanVersionText, 0.0f, 0.0f, UiTextStyle.small, [0.72f, 0.96f, 1.00f, 1.00f], smallTextHeight));
    content.add(new UiSpacer(0.0f, 4.0f));
    content.add(new UiLabel(format("FRAME RATE: %.0f FPS", fps), 0.0f, 0.0f, UiTextStyle.medium, [1.00f, 1.00f, 1.00f, 1.00f], mediumTextHeight));
    content.add(new UiSpacer(0.0f, 4.0f));
    content.add(new UiLabel(format("CAMERA YAW: %.1f DEGREES", yawAngle * 180.0f / cast(float)PI), 0.0f, 0.0f, UiTextStyle.small, [0.40f, 1.00f, 0.70f, 1.00f], smallTextHeight));
    content.add(new UiSpacer(0.0f, 4.0f));
    content.add(new UiLabel(format("CAMERA PITCH: %.1f DEGREES", pitchAngle * 180.0f / cast(float)PI), 0.0f, 0.0f, UiTextStyle.small, [0.50f, 0.86f, 1.00f, 1.00f], smallTextHeight));
    content.add(new UiSpacer(0.0f, 4.0f));
    content.add(new UiLabel(format("ACTIVE SHAPE: %s", shapeName), 0.0f, 0.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f], smallTextHeight));
    content.add(new UiSpacer(0.0f, 4.0f));
    content.add(new UiLabel(format("CURRENT MODE: %s", renderModeName), 0.0f, 0.0f, UiTextStyle.small, [1.00f, 0.90f, 0.45f, 1.00f], smallTextHeight));
    content.add(new UiSpacer(0.0f, 4.0f));
    content.add(new UiLabel(buildText, 0.0f, 0.0f, UiTextStyle.small, [0.86f, 0.96f, 1.00f, 1.00f], smallTextHeight));
    window.add(content);
    return window;
}

private UiWindow buildModeWindow(HudWindowRect rect, ref const(FontAtlas) smallFont, void delegate() onFlatColor = null, void delegate() onLitTextured = null, void delegate() onWireframe = null, void delegate() onHiddenLine = null, void delegate() onPreviousShape = null, void delegate() onNextShape = null, void delegate() onSettings = null, void delegate() onToggleStatus = null, void delegate() onToggleSample = null, void delegate() onToggleInput = null, void delegate() onToggleCenter = null)
{
    const buttonLabels = ["F  FLAT COLOR", "T  LIT / TEXTURED", "W  WIREFRAME", "H  HIDDEN LINE"];
    const actionLabels = ["MODEL -", "MODEL +", "STATUS", "SAMPLE", "LOG", "SETTINGS", "DRAG ME"];
    const buttonPadding = 12.0f;

    float buttonWidth = 0.0f;
    foreach (label; buttonLabels)
        buttonWidth = max(buttonWidth, textBlockWidth(smallFont, label));
    foreach (label; actionLabels)
        buttonWidth = max(buttonWidth, textBlockWidth(smallFont, label));
    buttonWidth += buttonPadding;

    const buttonRowWidth = buttonWidth * 2.0f + 4.0f;
    const contentWidth = buttonRowWidth;
    const width = contentWidth + 22.0f;
    const smallTextHeight = textBlockHeight(smallFont);
    const buttonHeight = max(smallTextHeight + 10.0f, 24.0f);
    const height = 28.0f + (buttonHeight * 4.0f + 12.0f + smallTextHeight * 2.0f) + 12.0f;

    auto window = new UiWindow("RENDER MODES", rect.left, rect.top, rect.width, rect.height, [0.10f, 0.12f, 0.16f, 0.94f], [0.14f, 0.16f, 0.20f, 0.96f], [1.00f, 0.98f, 0.82f, 1.00f]);
    auto content = new UiVBox(0.0f, 0.0f, max(rect.width - 22.0f, 0.0f), max(rect.height - 22.0f, 0.0f));

    auto topRow = new UiHBox(0.0f, 0.0f, buttonRowWidth, buttonHeight, 4.0f);
    auto flatColorButton = new UiButton("F  FLAT COLOR", 0.0f, 0.0f, buttonWidth, buttonHeight, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]);
    flatColorButton.onClick = onFlatColor;
    topRow.add(flatColorButton);
    auto litTexturedButton = new UiButton("T  LIT / TEXTURED", 0.0f, 0.0f, buttonWidth, buttonHeight, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]);
    litTexturedButton.onClick = onLitTextured;
    topRow.add(litTexturedButton);
    content.add(topRow);
    content.add(new UiSpacer(0.0f, 3.0f));

    auto bottomRow = new UiHBox(0.0f, 0.0f, buttonRowWidth, buttonHeight, 4.0f);
    auto wireframeButton = new UiButton("W  WIREFRAME", 0.0f, 0.0f, buttonWidth, buttonHeight, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]);
    wireframeButton.onClick = onWireframe;
    bottomRow.add(wireframeButton);
    auto hiddenLineButton = new UiButton("H  HIDDEN LINE", 0.0f, 0.0f, buttonWidth, buttonHeight, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]);
    hiddenLineButton.onClick = onHiddenLine;
    bottomRow.add(hiddenLineButton);
    content.add(bottomRow);

    content.add(new UiSpacer(0.0f, 3.0f));
    auto modelRow = new UiHBox(0.0f, 0.0f, buttonRowWidth, buttonHeight, 4.0f);
    auto previousShapeButton = new UiButton("MODEL -", 0.0f, 0.0f, buttonWidth, buttonHeight, [0.14f, 0.16f, 0.22f, 0.96f], [0.18f, 0.46f, 0.82f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]);
    previousShapeButton.onClick = onPreviousShape;
    modelRow.add(previousShapeButton);
    auto nextShapeButton = new UiButton("MODEL +", 0.0f, 0.0f, buttonWidth, buttonHeight, [0.14f, 0.16f, 0.22f, 0.96f], [0.18f, 0.46f, 0.82f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]);
    nextShapeButton.onClick = onNextShape;
    modelRow.add(nextShapeButton);
    content.add(modelRow);

    content.add(new UiSpacer(0.0f, 3.0f));
    auto windowRow = new UiHBox(0.0f, 0.0f, buttonRowWidth, buttonHeight, 4.0f);
    auto statusButton = new UiButton("STATUS", 0.0f, 0.0f, buttonWidth, buttonHeight, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]);
    statusButton.onClick = onToggleStatus;
    windowRow.add(statusButton);
    auto sampleButton = new UiButton("SAMPLE", 0.0f, 0.0f, buttonWidth, buttonHeight, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]);
    sampleButton.onClick = onToggleSample;
    windowRow.add(sampleButton);
    content.add(windowRow);

    auto secondWindowRow = new UiHBox(0.0f, 0.0f, buttonRowWidth, buttonHeight, 4.0f);
    auto logButton = new UiButton("LOG", 0.0f, 0.0f, buttonWidth, buttonHeight, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]);
    logButton.onClick = onToggleInput;
    secondWindowRow.add(logButton);
    auto settingsToggleButton = new UiButton("SETTINGS", 0.0f, 0.0f, buttonWidth, buttonHeight, [0.18f, 0.20f, 0.28f, 0.96f], [0.32f, 0.72f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]);
    settingsToggleButton.onClick = onSettings;
    secondWindowRow.add(settingsToggleButton);
    auto centerToggleButton = new UiButton("DRAG ME", 0.0f, 0.0f, buttonWidth, buttonHeight, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]);
    centerToggleButton.onClick = onToggleCenter;
    secondWindowRow.add(centerToggleButton);
    content.add(secondWindowRow);

    window.add(content);
    return window;
}

private UiWindow buildSettingsWindow(HudWindowRect rect, ref HudLayoutState layoutState, float extentWidth, float extentHeight, ref DemoSettings settingsDraft, void delegate() onApplySettings, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont)
{
    float[4] labelColor = [1.00f, 1.00f, 1.00f, 1.00f];
    float[4] accentColor = [0.86f, 0.96f, 1.00f, 1.00f];
    float[4] buttonFill = [0.16f, 0.18f, 0.24f, 0.96f];
    float[4] buttonBorder = [0.20f, 0.56f, 0.98f, 1.00f];
    float buttonHeight = max(cast(float)smallFont.lineHeight + 10.0f, 24.0f);
    float wideButton = max(110.0f, textBlockWidth(smallFont, "FULLSCREEN"));
    float valueButton = max(80.0f, textBlockWidth(smallFont, "1920 x 1080"));

    auto window = new UiWindow("SETTINGS", rect.left, rect.top, rect.width, rect.height, [0.09f, 0.11f, 0.15f, 0.96f], [0.14f, 0.16f, 0.20f, 0.98f], [1.00f, 0.98f, 0.82f, 1.00f], false, true, true);
    window.visible = layoutState.settingsVisible;
    window.dragTracking = layoutState.settingsDragging;
    window.onHeaderDragStart = (float cursorX, float cursorY)
    {
        hudBeginSettingsDrag(layoutState, rect, cursorX, cursorY);
    };
    window.onHeaderDragMove = (float cursorX, float cursorY)
    {
        hudSettingsDragTo(layoutState, cursorX, cursorY, extentWidth, extentHeight);
    };
    window.onHeaderDragEnd = ()
    {
        hudEndSettingsDrag(layoutState);
    };
    window.onClose = ()
    {
        layoutState.settingsVisible = false;
    };

    auto content = new UiVBox(0.0f, 0.0f, max(rect.width - 36.0f, 0.0f), max(rect.height - 36.0f, 0.0f), 6.0f);
    content.add(new UiLabel("VIDEO AND DISPLAY", 0.0f, 0.0f, UiTextStyle.medium, accentColor, cast(float)mediumFont.lineHeight));

    auto displayRow = new UiHBox(0.0f, 0.0f, 0.0f, buttonHeight, 4.0f);
    auto windowedButton = new UiButton("WINDOWED", 0.0f, 0.0f, wideButton, buttonHeight, buttonFill, buttonBorder, labelColor);
    windowedButton.onClick = ()
    {
        settingsDraft.display.windowMode = "windowed";
        settingsDraft.display.fullscreen = false;
    };
    displayRow.add(windowedButton);
    auto fullscreenButton = new UiButton("FULLSCREEN", 0.0f, 0.0f, wideButton, buttonHeight, buttonFill, buttonBorder, labelColor);
    fullscreenButton.onClick = ()
    {
        settingsDraft.display.windowMode = "fullscreen";
        settingsDraft.display.fullscreen = true;
    };
    displayRow.add(fullscreenButton);
    auto vsyncButton = new UiButton(settingsDraft.display.vsync ? "VSYNC ON" : "VSYNC OFF", 0.0f, 0.0f, wideButton, buttonHeight, buttonFill, buttonBorder, labelColor);
    vsyncButton.onClick = ()
    {
        settingsDraft.display.vsync = !settingsDraft.display.vsync;
    };
    displayRow.add(vsyncButton);
    content.add(displayRow);

    auto resolutionRow = new UiHBox(0.0f, 0.0f, 0.0f, buttonHeight, 4.0f);
    auto resolutionLabel = new UiLabel(format("RESOLUTION: %s x %s", settingsDraft.display.windowWidth, settingsDraft.display.windowHeight), 0.0f, 0.0f, UiTextStyle.small, labelColor, cast(float)smallFont.lineHeight);
    content.add(resolutionLabel);
    auto lowerResolutionButton = new UiButton("-", 0.0f, 0.0f, 36.0f, buttonHeight, buttonFill, buttonBorder, labelColor);
    lowerResolutionButton.onClick = ()
    {
        if (settingsDraft.display.windowWidth > 1024)
        {
            settingsDraft.display.windowWidth = 1280;
            settingsDraft.display.windowHeight = 720;
        }
        else
        {
            settingsDraft.display.windowWidth = 1024;
            settingsDraft.display.windowHeight = 576;
        }
    };
    resolutionRow.add(lowerResolutionButton);
    auto presetResolutionButton = new UiButton("1600 x 900", 0.0f, 0.0f, valueButton, buttonHeight, buttonFill, buttonBorder, labelColor);
    presetResolutionButton.onClick = ()
    {
        settingsDraft.display.windowWidth = 1600;
        settingsDraft.display.windowHeight = 900;
    };
    resolutionRow.add(presetResolutionButton);
    auto higherResolutionButton = new UiButton("1920 x 1080", 0.0f, 0.0f, valueButton, buttonHeight, buttonFill, buttonBorder, labelColor);
    higherResolutionButton.onClick = ()
    {
        settingsDraft.display.windowWidth = 1920;
        settingsDraft.display.windowHeight = 1080;
    };
    resolutionRow.add(higherResolutionButton);
    content.add(resolutionRow);

    content.add(new UiSpacer(0.0f, 6.0f));
    content.add(new UiLabel("GAMEPLAY AND INPUT", 0.0f, 0.0f, UiTextStyle.medium, accentColor, cast(float)mediumFont.lineHeight));
    auto gameplayRow = new UiHBox(0.0f, 0.0f, 0.0f, buttonHeight, 4.0f);
    auto flatButton = new UiButton("FLAT COLOR", 0.0f, 0.0f, wideButton, buttonHeight, buttonFill, buttonBorder, labelColor);
    flatButton.onClick = () { settingsDraft.gameplay.startupRenderMode = "flatColor"; };
    gameplayRow.add(flatButton);
    auto litButton = new UiButton("LIT TEXTURED", 0.0f, 0.0f, wideButton, buttonHeight, buttonFill, buttonBorder, labelColor);
    litButton.onClick = () { settingsDraft.gameplay.startupRenderMode = "litTextured"; };
    gameplayRow.add(litButton);
    auto wireButton = new UiButton("WIREFRAME", 0.0f, 0.0f, wideButton, buttonHeight, buttonFill, buttonBorder, labelColor);
    wireButton.onClick = () { settingsDraft.gameplay.startupRenderMode = "wireframe"; };
    gameplayRow.add(wireButton);
    auto hiddenButton = new UiButton("HIDDEN LINE", 0.0f, 0.0f, wideButton, buttonHeight, buttonFill, buttonBorder, labelColor);
    hiddenButton.onClick = () { settingsDraft.gameplay.startupRenderMode = "hiddenLine"; };
    gameplayRow.add(hiddenButton);
    content.add(gameplayRow);

    content.add(new UiSpacer(0.0f, 6.0f));
    content.add(new UiLabel("AUDIO AND UI", 0.0f, 0.0f, UiTextStyle.medium, accentColor, cast(float)mediumFont.lineHeight));
    auto uiRow = new UiHBox(0.0f, 0.0f, 0.0f, buttonHeight, 4.0f);
    auto compactButton = new UiButton(settingsDraft.ui.compactWindows ? "COMPACT ON" : "COMPACT OFF", 0.0f, 0.0f, wideButton, buttonHeight, buttonFill, buttonBorder, labelColor);
    compactButton.onClick = () { settingsDraft.ui.compactWindows = !settingsDraft.ui.compactWindows; };
    uiRow.add(compactButton);
    auto fontDownButton = new UiButton("FONT -", 0.0f, 0.0f, wideButton, buttonHeight, buttonFill, buttonBorder, labelColor);
    fontDownButton.onClick = () { settingsDraft.ui.fontScale = max(0.8f, settingsDraft.ui.fontScale - 0.1f); };
    uiRow.add(fontDownButton);
    auto fontUpButton = new UiButton("FONT +", 0.0f, 0.0f, wideButton, buttonHeight, buttonFill, buttonBorder, labelColor);
    fontUpButton.onClick = () { settingsDraft.ui.fontScale = min(1.6f, settingsDraft.ui.fontScale + 0.1f); };
    uiRow.add(fontUpButton);
    content.add(uiRow);

    content.add(new UiSpacer(0.0f, 2.0f));
    auto actionRow = new UiHBox(0.0f, 0.0f, 0.0f, buttonHeight, 4.0f);
    auto applyButton = new UiButton("APPLY", 0.0f, 0.0f, wideButton, buttonHeight, [0.20f, 0.34f, 0.22f, 0.96f], [0.28f, 0.80f, 0.46f, 1.00f], labelColor);
    applyButton.onClick = ()
    {
        if (onApplySettings !is null)
            onApplySettings();
        layoutState.settingsVisible = false;
    };
    actionRow.add(applyButton);
    auto resetButton = new UiButton("RESET", 0.0f, 0.0f, wideButton, buttonHeight, [0.22f, 0.20f, 0.16f, 0.96f], [0.82f, 0.66f, 0.28f, 1.00f], labelColor);
    resetButton.onClick = ()
    {
        settingsDraft = DemoSettings.init;
    };
    actionRow.add(resetButton);
    auto closeButton = new UiButton("CLOSE", 0.0f, 0.0f, wideButton, buttonHeight, [0.42f, 0.16f, 0.16f, 0.96f], [0.92f, 0.46f, 0.46f, 1.00f], labelColor);
    closeButton.onClick = ()
    {
        layoutState.settingsVisible = false;
    };
    actionRow.add(closeButton);
    content.add(actionRow);

    window.add(content);
    return window;
}

/** Sends a pointer event to the settings dialog and reports whether it handled it. */
bool hudDispatchSettingsWindowPointer(float extentWidth, float extentHeight, ref HudLayoutState layoutState, ref DemoSettings settingsDraft, float mouseX, float mouseY, UiPointerEventKind kind, uint button, void delegate() onApplySettings, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont)
{
    auto window = buildSettingsWindow(buildSettingsRect(extentWidth, extentHeight, layoutState), layoutState, extentWidth, extentHeight, settingsDraft, onApplySettings, smallFont, mediumFont);
    UiPointerEvent event;
    event.kind = kind;
    event.x = mouseX;
    event.y = mouseY;
    event.button = button;
    return window.dispatchPointerEvent(event);
}

/** Sends a button-down event to the mode buttons and reports whether one handled it. */
bool hudDispatchModeButtonDown(HudWindowRect rect, float mouseX, float mouseY, ref const(FontAtlas) smallFont, void delegate() onFlatColor, void delegate() onLitTextured, void delegate() onWireframe, void delegate() onHiddenLine, void delegate() onPreviousShape, void delegate() onNextShape, void delegate() onSettings, void delegate() onToggleStatus, void delegate() onToggleSample, void delegate() onToggleInput, void delegate() onToggleCenter)
{
    auto window = buildModeWindow(rect, smallFont, onFlatColor, onLitTextured, onWireframe, onHiddenLine, onPreviousShape, onNextShape, onSettings, onToggleStatus, onToggleSample, onToggleInput, onToggleCenter);
    UiPointerEvent event;
    event.kind = UiPointerEventKind.buttonDown;
    event.x = mouseX;
    event.y = mouseY;
    event.button = 1;
    return window.dispatchPointerEvent(event);
}

/** Sends a pointer event to the status window and reports whether it handled it. */
bool hudDispatchStatusWindowPointer(HudWindowRect rect, ref HudLayoutState layoutState, float fps, float yawAngle, float pitchAngle, string shapeName, string renderModeName, string buildVersion, string platformName, uint vulkanApiVersion, float mouseX, float mouseY, UiPointerEventKind kind, uint button, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont)
{
    auto window = buildStatusWindow(rect, layoutState, fps, yawAngle, pitchAngle, shapeName, renderModeName, buildVersion, platformName, vulkanApiVersion, smallFont, mediumFont);
    UiPointerEvent event;
    event.kind = kind;
    event.x = mouseX;
    event.y = mouseY;
    event.button = button;
    return window.dispatchPointerEvent(event);
}

private UiWindow buildSampleWindow(HudWindowRect rect, const(FontAtlas)[] fontAtlases, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont, ref const(FontAtlas) largeFont)
{
    const sample7Width = textBlockWidth(smallFont, "7 PX  THE QUICK BROWN FOX");
    const sample8Width = textBlockWidth(smallFont, "8 PX  THE QUICK BROWN FOX");
    const sample9Width = textBlockWidth(mediumFont, "9 PX  THE QUICK BROWN FOX");
    const sample10Width = textBlockWidth(mediumFont, "10 PX THE QUICK BROWN FOX");
    const sample11Width = textBlockWidth(largeFont, "11 PX THE QUICK BROWN FOX");
    const sample12Width = textBlockWidth(largeFont, "12 PX THE QUICK BROWN FOX");
    const sampleMonoWidth = textBlockWidth(largeFont, "8 PX MONO THE QUICK BROWN FOX");
    const contentWidth = max(max(sample7Width, sample8Width), max(max(sample9Width, sample10Width), max(max(sample11Width, sample12Width), sampleMonoWidth)));
    const width = contentWidth + 36.0f;
    const smallTextHeight = textBlockHeight(smallFont);
    const mediumTextHeight = textBlockHeight(mediumFont);
    const largeTextHeight = textBlockHeight(largeFont);
    const contentBottom = max(max(max(max(max(max(
        0.0f + smallTextHeight,
        4.0f + smallTextHeight),
        8.0f + mediumTextHeight),
        12.0f + mediumTextHeight),
        16.0f + largeTextHeight),
        20.0f + largeTextHeight),
        24.0f + largeTextHeight);
    const height = 32.0f + contentBottom + 12.0f;

    auto window = new UiWindow("FONT SAMPLE", rect.left, rect.top, rect.width, rect.height, [0.10f, 0.12f, 0.16f, 0.94f], [0.14f, 0.16f, 0.20f, 0.96f], [1.00f, 0.98f, 0.82f, 1.00f]);
    auto content = new UiVBox(0.0f, 0.0f, max(rect.width - 28.0f, 0.0f), max(rect.height - 28.0f, 0.0f), 2.0f);
    content.add(new UiLabel("7 PX  THE QUICK BROWN FOX", 0.0f, 0.0f, UiTextStyle.sample7, [1.00f, 1.00f, 1.00f, 1.00f], smallTextHeight));
    content.add(new UiLabel("8 PX  THE QUICK BROWN FOX", 0.0f, 0.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f], smallTextHeight));
    content.add(new UiLabel("9 PX  THE QUICK BROWN FOX", 0.0f, 0.0f, UiTextStyle.sample9, [1.00f, 1.00f, 1.00f, 1.00f], mediumTextHeight));
    content.add(new UiLabel("10 PX THE QUICK BROWN FOX", 0.0f, 0.0f, UiTextStyle.medium, [1.00f, 1.00f, 1.00f, 1.00f], mediumTextHeight));
    content.add(new UiLabel("11 PX THE QUICK BROWN FOX", 0.0f, 0.0f, UiTextStyle.sample11, [1.00f, 1.00f, 1.00f, 1.00f], largeTextHeight));
    content.add(new UiLabel("12 PX THE QUICK BROWN FOX", 0.0f, 0.0f, UiTextStyle.large, [1.00f, 1.00f, 1.00f, 1.00f], largeTextHeight));
    const monoTextHeight = textBlockHeight(fontAtlases[6]);
    content.add(new UiLabel("10 PX MONO THE QUICK BROWN FOX", 0.0f, 0.0f, UiTextStyle.sampleMono, [1.00f, 1.00f, 1.00f, 1.00f], monoTextHeight));
    window.add(content);
    return window;
}

private UiWindow buildInputWindow(HudWindowRect rect, ref const(FontAtlas) smallFont)
{
    auto window = new UiWindow("LOG", rect.left, rect.top, rect.width, rect.height, [0.10f, 0.12f, 0.16f, 0.92f], [0.14f, 0.16f, 0.20f, 0.96f], [1.00f, 0.98f, 0.82f, 1.00f]);
    auto content = new UiVBox(0.0f, 0.0f, max(rect.width - 28.0f, 0.0f), max(rect.height - 28.0f, 0.0f), 4.0f);
    content.add(new UiTextBlock("INPUT WINDOW BECOMES A LOG WINDOW.\n\n- FUTURE CONSOLE TARGET\n- MULTILINE RETAINED TEXT\n- EVENT AND DIAGNOSTICS OUTPUT\n- READY FOR ADMIN COMMANDS", 0.0f, 0.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f], smallFont.lineHeight * 7.0f));
    window.add(content);
    return window;
}

private UiWindow buildCenterWindow(HudWindowRect rect, ref HudLayoutState layoutState, float extentWidth, float extentHeight, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont)
{
    auto window = new UiWindow("DRAG ME", rect.left, rect.top, rect.width, rect.height, [0.10f, 0.12f, 0.16f, 0.92f], [0.14f, 0.16f, 0.20f, 0.96f], [1.00f, 0.98f, 0.82f, 1.00f], true, true, true);
    window.visible = layoutState.centerVisible;
    window.onClose = ()
    {
        logLine("UiWindow close: DRAG ME");
        layoutState.centerVisible = false;
        layoutState.middleDragging = false;
        layoutState.middleResizing = false;
        layoutState.middleResizeHandle = UiResizeHandle.none;
    };
    auto content = new UiVBox(0.0f, 0.0f, max(rect.width - 28.0f, 0.0f), max(rect.height - 28.0f, 0.0f), 4.0f);
    content.add(new UiLabel("DRAG ME", 0.0f, 0.0f, UiTextStyle.medium, [0.86f, 0.96f, 1.00f, 1.00f], mediumFont.lineHeight));
    content.add(new UiTextBlock("- USE THE BLUE HEADER BAR TO DRAG\n- RESIZE FROM THE CORNERS\n- THIS WINDOW IS THE RELAYOUT TEST BED\n- GOOD PLACE TO CHECK VBOX/HBOX BEHAVIOR", 0.0f, 0.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f], smallFont.lineHeight * 5.0f));
    auto footerRow = new UiHBox(0.0f, 0.0f, 0.0f, smallFont.lineHeight, 6.0f);
    footerRow.add(new UiLabel("HEADER = DRAG", 0.0f, 0.0f, UiTextStyle.small, [0.90f, 0.95f, 1.00f, 1.00f], smallFont.lineHeight));
    footerRow.add(new UiLabel("CORNERS = RESIZE", 0.0f, 0.0f, UiTextStyle.small, [0.90f, 0.95f, 1.00f, 1.00f], smallFont.lineHeight));
    content.add(footerRow);
    window.add(content);
    window.dragTracking = layoutState.middleDragging;
    window.resizeTracking = layoutState.middleResizing;
    window.resizeHandle = layoutState.middleResizeHandle;
    window.onHeaderDragStart = (float cursorX, float cursorY)
    {
        hudBeginDrag(layoutState, rect, cursorX, cursorY);
    };
    window.onHeaderDragMove = (float cursorX, float cursorY)
    {
        hudDragTo(layoutState, cursorX, cursorY, extentWidth, extentHeight);
    };
    window.onHeaderDragEnd = ()
    {
        hudEndDrag(layoutState);
    };
    window.onResizeStart = (UiResizeHandle handle)
    {
        hudBeginResize(layoutState, handle, rect);
    };
    window.onResizeMove = (UiResizeHandle handle, float cursorX, float cursorY)
    {
        hudResizeTo(layoutState, handle, cursorX, cursorY, extentWidth, extentHeight);
    };
    window.onResizeEnd = (UiResizeHandle handle)
    {
        hudEndResize(layoutState, handle);
    };
    return window;
}

/** Sends center-window pointer events through the retained widget tree. */
bool hudDispatchCenterWindowPointer(HudWindowRect rect, ref HudLayoutState layoutState, float extentWidth, float extentHeight, float mouseX, float mouseY, UiPointerEventKind kind, uint button, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont)
{
    auto window = buildCenterWindow(rect, layoutState, extentWidth, extentHeight, smallFont, mediumFont);
    UiPointerEvent event;
    event.kind = kind;
    event.x = mouseX;
    event.y = mouseY;
    event.button = button;
    return window.dispatchPointerEvent(event);
}

HudWindowRect buildSettingsRect(float extentWidth, float extentHeight, ref HudLayoutState layoutState)
{
    const preferredWidth = 560.0f;
    const preferredHeight = 470.0f;
    const width = min(preferredWidth, max(extentWidth - 80.0f, 360.0f));
    const height = min(preferredHeight, max(extentHeight - 80.0f, 320.0f));

    if (!layoutState.settingsInitialized)
    {
        layoutState.settingsWidth = width;
        layoutState.settingsHeight = height;
        layoutState.settingsLeft = max((extentWidth - width) * 0.5f, 20.0f);
        layoutState.settingsTop = max((extentHeight - height) * 0.5f, 20.0f);
        layoutState.settingsInitialized = true;
    }

    layoutState.settingsWidth = max(layoutState.settingsWidth, width);
    layoutState.settingsHeight = max(layoutState.settingsHeight, height);

    const maximumLeft = extentWidth > layoutState.settingsWidth ? extentWidth - layoutState.settingsWidth : 0.0f;
    const maximumTop = extentHeight > layoutState.settingsHeight ? extentHeight - layoutState.settingsHeight : 0.0f;
    layoutState.settingsLeft = clampFloat(layoutState.settingsLeft, 0.0f, maximumLeft);
    layoutState.settingsTop = clampFloat(layoutState.settingsTop, 0.0f, maximumTop);

    return HudWindowRect(layoutState.settingsLeft, layoutState.settingsTop, layoutState.settingsWidth, layoutState.settingsHeight);
}

private HudWindowRect buildStatusRect(float extentWidth, float extentHeight, float fps, float yawAngle, float pitchAngle, string shapeName, string renderModeName, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont)
{
    const titleWidth = textBlockWidth(mediumFont, "STATUS");
    const contentWidth = max(
        max(
            max(textBlockWidth(smallFont, "PLATFORM: X"), textBlockWidth(smallFont, "VULKAN API: 1.3.0")),
            max(textBlockWidth(mediumFont, "FRAME RATE: 999 FPS"), textBlockWidth(smallFont, "CAMERA PITCH: 999.9 DEGREES"))),
        max(
            max(textBlockWidth(smallFont, "CAMERA YAW: 999.9 DEGREES"), textBlockWidth(smallFont, "ACTIVE SHAPE: ICOSAHEDRON")),
            max(textBlockWidth(smallFont, "CURRENT MODE: HIDDEN LINE"), textBlockWidth(smallFont, "BUILD: X"))));
    const width = max(titleWidth + 18.0f, contentWidth + 24.0f);
    const smallTextHeight = textBlockHeight(smallFont);
    const mediumTextHeight = textBlockHeight(mediumFont);
    const height = 32.0f + (smallTextHeight * 6.0f + mediumTextHeight + 6.0f * 6.0f) + 16.0f;
    return HudWindowRect(18.0f, 18.0f, width, height);
}

private HudWindowRect buildModesRect(float extentWidth, float extentHeight, ref const(FontAtlas) smallFont)
{
    const buttonLabels = ["F  FLAT COLOR", "T  LIT / TEXTURED", "W  WIREFRAME", "H  HIDDEN LINE", "MODEL -", "MODEL +", "STATUS", "SAMPLE", "LOG", "SETTINGS"];
    const buttonPadding = 12.0f;
    float buttonWidth = 0.0f;
    foreach (label; buttonLabels)
        buttonWidth = max(buttonWidth, textBlockWidth(smallFont, label));
    buttonWidth += buttonPadding;

    const buttonRowWidth = buttonWidth * 2.0f + 4.0f;
    const width = max(buttonRowWidth + 24.0f, 360.0f);
    const smallTextHeight = textBlockHeight(smallFont);
    const buttonHeight = max(smallTextHeight + 10.0f, 24.0f);
    const height = 32.0f + (buttonHeight * 4.0f + 12.0f + smallTextHeight * 2.0f + 16.0f) + 16.0f;
    return HudWindowRect(max(18.0f, extentWidth - 18.0f - width), 18.0f, width, height);
}

private HudWindowRect buildSampleRect(float extentWidth, float extentHeight, const(FontAtlas)[] fontAtlases)
{
    const sample7Width = textBlockWidth(fontAtlases[3], "7 PX  THE QUICK BROWN FOX");
    const sample8Width = textBlockWidth(fontAtlases[0], "8 PX  THE QUICK BROWN FOX");
    const sample9Width = textBlockWidth(fontAtlases[4], "9 PX  THE QUICK BROWN FOX");
    const sample10Width = textBlockWidth(fontAtlases[1], "10 PX THE QUICK BROWN FOX");
    const sample11Width = textBlockWidth(fontAtlases[5], "11 PX THE QUICK BROWN FOX");
    const sample12Width = textBlockWidth(fontAtlases[2], "12 PX THE QUICK BROWN FOX");
    const sampleMonoWidth = textBlockWidth(fontAtlases[6], "10 PX MONO THE QUICK BROWN FOX");
    const contentWidth = max(max(sample7Width, sample8Width), max(max(sample9Width, sample10Width), max(max(sample11Width, sample12Width), sampleMonoWidth)));
    const width = contentWidth + 36.0f;
    const smallTextHeight = textBlockHeight(fontAtlases[0]);
    const mediumTextHeight = textBlockHeight(fontAtlases[1]);
    const largeTextHeight = textBlockHeight(fontAtlases[2]);
    const monoTextHeight = textBlockHeight(fontAtlases[6]);
    const contentHeight = smallTextHeight * 3.0f + mediumTextHeight * 2.0f + largeTextHeight * 2.0f + monoTextHeight + 2.0f * 6.0f;
    const height = 32.0f + contentHeight + 16.0f;
    return HudWindowRect(18.0f, max(18.0f, extentHeight - 18.0f - height), width, height);
}

private HudWindowRect buildInputRect(float extentWidth, float extentHeight, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont)
{
    const titleWidth = textBlockWidth(mediumFont, "LOG");
    const lineOne = textBlockWidth(smallFont, "INPUT WINDOW BECOMES A LOG WINDOW.");
    const lineTwo = textBlockWidth(smallFont, "FUTURE ADMIN CONSOLE / MULTILINE TEXT BASE.");
    const lineThree = textBlockWidth(smallFont, "EVENTS, DIAGNOSTICS, COMMANDS, AND NOTES.");
    const contentWidth = max(max(lineOne, lineTwo), lineThree);
    const width = max(titleWidth + 24.0f, contentWidth + 36.0f);
    const smallTextHeight = textBlockHeight(smallFont);
    const mediumTextHeight = textBlockHeight(mediumFont);
    const height = 36.0f + max(max(0.0f + smallTextHeight, smallTextHeight * 2.0f + 12.0f), smallTextHeight * 6.0f + 28.0f) + 20.0f;
    return HudWindowRect(max(18.0f, extentWidth - 18.0f - width), max(18.0f, extentHeight - 18.0f - height), width, height);
}

private HudWindowRect buildCenterRect(float extentWidth, float extentHeight, ref HudLayoutState layoutState, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont)
{
    const titleWidth = textBlockWidth(mediumFont, "DRAG ME");
    const lineOne = textBlockWidth(smallFont, "USE THE BLUE HEADER BAR TO DRAG.");
    const lineTwo = textBlockWidth(smallFont, "RESIZE FROM THE CORNERS.");
    const lineThree = textBlockWidth(smallFont, "THIS WINDOW IS THE RELAYOUT TEST BED.");
    const lineFour = textBlockWidth(smallFont, "GOOD FOR CHECKING VBOX / HBOX REFLOW.");
    const contentWidth = max(max(lineOne, lineTwo), max(lineThree, lineFour));
    const measuredWidth = max(titleWidth + 24.0f, contentWidth + 36.0f);
    const smallTextHeight = textBlockHeight(smallFont);
    const mediumTextHeight = textBlockHeight(mediumFont);
    const measuredHeight = 36.0f + max(max(max(0.0f + smallTextHeight, smallTextHeight * 2.0f + 12.0f), smallTextHeight * 5.0f + 20.0f), smallTextHeight * 5.0f + 40.0f) + 20.0f;

    layoutState.middleMinimumWidth = measuredWidth;
    layoutState.middleMinimumHeight = measuredHeight;

    const width = layoutState.middleInitialized ? max(layoutState.middleWidth, measuredWidth) : measuredWidth;
    const height = layoutState.middleInitialized ? max(layoutState.middleHeight, measuredHeight) : measuredHeight;

    layoutState.middleWidth = width;
    layoutState.middleHeight = height;
    if (!layoutState.middleInitialized)
    {
        layoutState.middleLeft = (extentWidth - width) * 0.5f;
        layoutState.middleTop = (extentHeight - height) * 0.5f;
        layoutState.middleInitialized = true;
    }

    const maximumLeft = extentWidth > width ? extentWidth - width : 0.0f;
    const maximumTop = extentHeight > height ? extentHeight - height : 0.0f;
    layoutState.middleLeft = clampFloat(layoutState.middleLeft, 0.0f, maximumLeft);
    layoutState.middleTop = clampFloat(layoutState.middleTop, 0.0f, maximumTop);

    return HudWindowRect(layoutState.middleLeft, layoutState.middleTop, width, height);
}

/** Starts dragging the settings window from the supplied cursor position. */
void hudBeginSettingsDrag(ref HudLayoutState state, HudWindowRect rect, float cursorX, float cursorY)
{
    logLine("Settings drag start at ", cursorX, ", ", cursorY);
    state.settingsDragging = true;
    state.settingsDragOffsetX = cursorX - rect.left;
    state.settingsDragOffsetY = cursorY - rect.top;
}

/** Updates the dragged settings window position and clamps it to the viewport. */
void hudSettingsDragTo(ref HudLayoutState state, float cursorX, float cursorY, float extentWidth, float extentHeight)
{
    if (!state.settingsDragging)
        return;

    const windowWidth = state.settingsWidth > 0.0f ? state.settingsWidth : 360.0f;
    const windowHeight = state.settingsHeight > 0.0f ? state.settingsHeight : 320.0f;
    const newLeft = cursorX - state.settingsDragOffsetX;
    const newTop = cursorY - state.settingsDragOffsetY;
    const maximumLeft = extentWidth > windowWidth ? extentWidth - windowWidth : 0.0f;
    const maximumTop = extentHeight > windowHeight ? extentHeight - windowHeight : 0.0f;
    state.settingsLeft = clampFloat(newLeft, 0.0f, maximumLeft);
    state.settingsTop = clampFloat(newTop, 0.0f, maximumTop);
}

/** Stops any active settings-window drag. */
void hudEndSettingsDrag(ref HudLayoutState state)
{
    logLine("Settings drag end");
    state.settingsDragging = false;
}

private float anchoredLayoutPosition(float preferredPosition, float widgetSpan, float availableSpan)
{
    if (availableSpan <= widgetSpan)
        return 0.0f;

    const maximumPosition = availableSpan - widgetSpan;
    return preferredPosition < maximumPosition ? preferredPosition : maximumPosition;
}

private float textBlockWidth(ref const(FontAtlas) atlas, string text)
{
    float currentWidth = 0.0f;
    float widestWidth = 0.0f;

    foreach (ch; text)
    {
        if (ch == '\n')
        {
            widestWidth = currentWidth > widestWidth ? currentWidth : widestWidth;
            currentWidth = 0.0f;
            continue;
        }

        const glyphPtr = ch in atlas.glyphs;
        if (glyphPtr !is null)
            currentWidth += glyphPtr.advance > 0.0f ? glyphPtr.advance : atlas.pixelHeight * 0.6f;
        else if (auto fallbackPtr = '?' in atlas.glyphs)
            currentWidth += fallbackPtr.advance > 0.0f ? fallbackPtr.advance : atlas.pixelHeight * 0.6f;
        else
            currentWidth += atlas.pixelHeight * 0.6f;
    }

    return currentWidth > widestWidth ? currentWidth : widestWidth;
}

private float textBlockHeight(ref const(FontAtlas) atlas)
{
    return max(atlas.lineHeight, atlas.ascent + atlas.descent);
}

/** Returns true when the pixel position lies within a HUD window rectangle. */
bool hudPointInRect(HudWindowRect rect, float x, float y)
{
    return x >= rect.left && x <= rect.left + rect.width && y >= rect.top && y <= rect.top + rect.height;
}

/** Returns true when the pixel position lies within the draggable header bar. */
bool hudPointInHeader(HudWindowRect rect, float x, float y)
{
    return hudPointInRect(HudWindowRect(rect.left, rect.top, rect.width, 7.0f), x, y);
}

/** Starts dragging the center window from the supplied cursor position. */
void hudBeginDrag(ref HudLayoutState state, HudWindowRect rect, float cursorX, float cursorY)
{
    logLine("Hud drag start at ", cursorX, ", ", cursorY);
    state.middleDragging = true;
    state.middleResizing = false;
    state.dragOffsetX = cursorX - rect.left;
    state.dragOffsetY = cursorY - rect.top;
}

/** Starts resizing the center window from one of its corner grips. */
void hudBeginResize(ref HudLayoutState state, UiResizeHandle handle, HudWindowRect rect)
{
    logLine("Hud resize start [", handle, "] at ", rect.left, ", ", rect.top);
    state.middleResizing = true;
    state.middleDragging = false;
    state.middleResizeHandle = handle;
    state.middleResizeStartLeft = rect.left;
    state.middleResizeStartTop = rect.top;
    state.middleResizeStartWidth = rect.width;
    state.middleResizeStartHeight = rect.height;
}

/** Updates the dragged center window position and clamps it to the viewport. */
void hudDragTo(ref HudLayoutState state, float cursorX, float cursorY, float extentWidth, float extentHeight)
{
    if (!state.middleDragging)
        return;

    const newLeft = cursorX - state.dragOffsetX;
    const newTop = cursorY - state.dragOffsetY;
    const maximumLeft = extentWidth > state.middleWidth ? extentWidth - state.middleWidth : 0.0f;
    const maximumTop = extentHeight > state.middleHeight ? extentHeight - state.middleHeight : 0.0f;
    state.middleLeft = clampFloat(newLeft, 0.0f, maximumLeft);
    state.middleTop = clampFloat(newTop, 0.0f, maximumTop);
}

/** Updates the resized center window geometry and clamps it to the viewport. */
void hudResizeTo(ref HudLayoutState state, UiResizeHandle handle, float cursorX, float cursorY, float extentWidth, float extentHeight)
{
    if (!state.middleResizing)
        return;

    const minimumWidth = state.middleMinimumWidth > 0.0f ? state.middleMinimumWidth : 240.0f;
    const minimumHeight = state.middleMinimumHeight > 0.0f ? state.middleMinimumHeight : 168.0f;
    const startLeft = state.middleResizeStartLeft;
    const startTop = state.middleResizeStartTop;
    const startRight = state.middleResizeStartLeft + state.middleResizeStartWidth;
    const startBottom = state.middleResizeStartTop + state.middleResizeStartHeight;

    final switch (handle)
    {
        case UiResizeHandle.topLeft:
        {
            const newLeft = clampFloat(cursorX, 0.0f, startRight - minimumWidth);
            const newTop = clampFloat(cursorY, 0.0f, startBottom - minimumHeight);
            state.middleLeft = newLeft;
            state.middleTop = newTop;
            state.middleWidth = startRight - newLeft;
            state.middleHeight = startBottom - newTop;
            break;
        }
        case UiResizeHandle.topRight:
        {
            const availableRight = extentWidth > startLeft ? extentWidth - startLeft : 0.0f;
            const newTop = clampFloat(cursorY, 0.0f, startBottom - minimumHeight);
            state.middleTop = newTop;
            state.middleWidth = clampFloat(cursorX - startLeft, minimumWidth, availableRight);
            state.middleHeight = startBottom - newTop;
            break;
        }
        case UiResizeHandle.bottomLeft:
        {
            const availableBottom = extentHeight > startTop ? extentHeight - startTop : 0.0f;
            const newLeft = clampFloat(cursorX, 0.0f, startRight - minimumWidth);
            state.middleLeft = newLeft;
            state.middleWidth = startRight - newLeft;
            state.middleHeight = clampFloat(cursorY - startTop, minimumHeight, availableBottom);
            break;
        }
        case UiResizeHandle.bottomRight:
        {
            const availableWidth = extentWidth > startLeft ? extentWidth - startLeft : 0.0f;
            const availableHeight = extentHeight > startTop ? extentHeight - startTop : 0.0f;
            state.middleWidth = clampFloat(cursorX - startLeft, minimumWidth, availableWidth);
            state.middleHeight = clampFloat(cursorY - startTop, minimumHeight, availableHeight);
            break;
        }
        case UiResizeHandle.none:
            break;
    }
}

/** Stops any active center-window drag. */
void hudEndDrag(ref HudLayoutState state)
{
    logLine("Hud drag end");
    state.middleDragging = false;
}

/** Stops any active center-window resize. */
void hudEndResize(ref HudLayoutState state, UiResizeHandle handle)
{
    logLine("Hud resize end [", handle, "]");
    state.middleResizing = false;
    state.middleResizeHandle = UiResizeHandle.none;
}

private float clampFloat(float value, float minimum, float maximum)
{
    return value < minimum ? minimum : (value > maximum ? maximum : value);
}
