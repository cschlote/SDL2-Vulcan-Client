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
import vulkan.font.font_legacy : FontAtlas, measureTextWidth;
import vulkan.engine.pipeline : Vertex;
import vulkan.ui.ui_event : UiPointerEvent, UiPointerEventKind, UiResizeHandle;
import vulkan.ui.ui_context : UiRenderContext, UiTextStyle;
import vulkan.ui.ui_button : UiButton;
import vulkan.ui.ui_container : UiContainer;
import vulkan.ui.ui_label : UiLabel, UiTextBlock;
import vulkan.ui.ui_layout : UiHBox, UiSpacer, UiVBox;
import vulkan.ui.ui_layout_context : UiLayoutContext;
import vulkan.ui.ui_layout_context : UiLayoutSize;
import vulkan.ui.ui_window : UiWindow;
import vulkan.ui.ui_widget : UiWidget;
import vulkan.ui.ui_widget_helpers : appendSurfaceFrame;
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
    bool settingsVisible = false;
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

    const layout = buildHudLayout(extentWidth, extentHeight, fps, yawAngle, pitchAngle, shapeName, renderModeName, buildVersion, platformName, vulkanApiVersion, layoutState, fontAtlases, smallFont, mediumFont, largeFont);
    UiWindow[] windows;
    if (layoutState.statusVisible)
        windows ~= buildStatusWindow(layout.status, layoutState, fps, yawAngle, pitchAngle, shapeName, renderModeName, buildVersion, platformName, vulkanApiVersion, smallFont, mediumFont);
    windows ~= buildModeWindow(
        layout.modes,
        mediumFont,
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
        windows ~= buildSampleWindow(layout.sample, fontAtlases);
    if (layoutState.inputVisible)
        windows ~= buildInputWindow(layout.input, smallFont);
    windows ~= buildCenterWindow(layout.center, layoutState, extentWidth, extentHeight, smallFont, mediumFont);
    windows ~= buildSettingsWindow(buildSettingsRect(extentWidth, extentHeight, layoutState, mediumFont), layoutState, extentWidth, extentHeight, settingsDraft, onApplySettings, smallFont, mediumFont);

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
HudLayout buildHudLayout(float extentWidth, float extentHeight, float fps, float yawAngle, float pitchAngle, string shapeName, string renderModeName, string buildVersion, string platformName, uint vulkanApiVersion, ref HudLayoutState layoutState, const(FontAtlas)[] fontAtlases, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont, ref const(FontAtlas) largeFont)
{
    HudLayout layout;
    layout.status = buildStatusRect(extentWidth, extentHeight, fps, yawAngle, pitchAngle, shapeName, renderModeName, buildVersion, platformName, vulkanApiVersion, smallFont, mediumFont);
    layout.modes = buildModesRect(extentWidth, extentHeight, mediumFont);
    layout.sample = buildSampleRect(extentWidth, extentHeight, fontAtlases);
    layout.input = buildInputRect(extentWidth, extentHeight, smallFont, mediumFont);
    layout.center = buildCenterRect(extentWidth, extentHeight, layoutState, smallFont, mediumFont);
    return layout;
}

private struct StatusWindowMetrics
{
    float labelWidth;
    float valueWidth;
    float rowHeight;
    float rowSpacing;
    float contentWidth;
    float contentHeight;
}

private enum float statusWindowMargin = 18.0f;
private enum float statusWindowTitlePaddingX = 24.0f;
private enum float statusWindowContentPaddingX = 32.0f;
private enum float statusWindowTitleHeight = 32.0f;
private enum float statusWindowFooterPadding = 16.0f;
private enum float statusWindowRowGap = 4.0f;
private enum float statusWindowColumnGap = 16.0f;
private enum float statusWindowInnerWidthPadding = 28.0f;
private enum float statusWindowInnerHeightPadding = 28.0f;
private enum float statusWindowTitleTextPadding = 2.0f;
private enum float statusWindowHeaderTextPadding = 0.72f; // Default accent for platform/version labels.
private enum float statusWindowLabelWidthFallback = 0.0f;
private enum float statusWindowValueWidthFallback = 0.0f;

private immutable float[4] statusWindowBodyColor = [0.10f, 0.12f, 0.16f, 0.96f];
private immutable float[4] statusWindowHeaderColor = [0.14f, 0.16f, 0.20f, 0.96f];
private immutable float[4] statusWindowTitleColor = [1.00f, 0.98f, 0.82f, 1.00f];
private immutable float[4] statusWindowPlatformColor = [0.72f, 0.96f, 1.00f, 1.00f];
private immutable float[4] statusWindowBodyTextColor = [1.00f, 1.00f, 1.00f, 1.00f];
private immutable float[4] statusWindowYawColor = [0.40f, 1.00f, 0.70f, 1.00f];
private immutable float[4] statusWindowPitchColor = [0.50f, 0.86f, 1.00f, 1.00f];
private immutable float[4] statusWindowModeColor = [1.00f, 0.90f, 0.45f, 1.00f];
private immutable float[4] statusWindowBuildColor = [0.86f, 0.96f, 1.00f, 1.00f];

private enum size_t statusRowPlatform = 0;
private enum size_t statusRowVulkan = 1;
private enum size_t statusRowFrameRate = 2;
private enum size_t statusRowYaw = 3;
private enum size_t statusRowPitch = 4;
private enum size_t statusRowShape = 5;
private enum size_t statusRowMode = 6;
private enum size_t statusRowBuild = 7;
private enum size_t statusRowCount = 8;

private StatusWindowMetrics measureStatusWindow(float fps, float yawAngle, float pitchAngle, string shapeName, string renderModeName, string buildVersion, string platformName, uint vulkanApiVersion, ref const(FontAtlas) mediumFont)
{
    StatusWindowMetrics metrics;
    const valueTextHeight = textBlockHeight(mediumFont);
    metrics.rowHeight = valueTextHeight;
    metrics.rowSpacing = statusWindowRowGap;

    const labelTexts = ["PLATFORM:", "VULKAN API:", "FRAME RATE:", "CAMERA YAW:", "CAMERA PITCH:", "ACTIVE SHAPE:", "CURRENT MODE:", "BUILD:"];
    const valueTexts = [
        platformName,
        format("%u.%u.%u", cast(uint)(vulkanApiVersion >> 22), cast(uint)((vulkanApiVersion >> 12) & 0x3ff), cast(uint)(vulkanApiVersion & 0xfff)),
        format("%.0f FPS", fps),
        format("%.1f DEGREES", yawAngle * 180.0f / cast(float)PI),
        format("%.1f DEGREES", pitchAngle * 180.0f / cast(float)PI),
        shapeName,
        renderModeName,
        buildVersion,
    ];
    metrics.labelWidth = statusWindowLabelWidthFallback;
    metrics.valueWidth = statusWindowValueWidthFallback;
    foreach (labelText; labelTexts)
        metrics.labelWidth = max(metrics.labelWidth, textBlockWidth(mediumFont, labelText));
    foreach (valueText; valueTexts)
        metrics.valueWidth = max(metrics.valueWidth, textBlockWidth(mediumFont, valueText));

    metrics.contentWidth = metrics.labelWidth + statusWindowColumnGap + metrics.valueWidth;
    metrics.contentHeight = cast(float)statusRowCount * metrics.rowHeight + cast(float)(statusRowCount - 1) * metrics.rowSpacing;
    return metrics;
}

/** Builds a layout-time font context for retained UI measurement.
 *
 * Params:
 *   fontSmall = Font atlas used for compact body copy and monospace samples.
 *   fontMedium = Font atlas used for labels, buttons, and window titles.
 *
 * Returns:
 *   A context that widgets can use during explicit measurement and layout.
 */
private UiLayoutContext buildLayoutContext(ref const(FontAtlas) fontSmall, ref const(FontAtlas) fontMedium)
{
    UiLayoutContext layoutContext;
    layoutContext.fonts[cast(size_t)UiTextStyle.small] = &fontSmall;
    layoutContext.fonts[cast(size_t)UiTextStyle.medium] = &fontMedium;
    layoutContext.fonts[cast(size_t)UiTextStyle.large] = &fontMedium;
    layoutContext.fonts[cast(size_t)UiTextStyle.sample7] = &fontSmall;
    layoutContext.fonts[cast(size_t)UiTextStyle.sample8] = &fontSmall;
    layoutContext.fonts[cast(size_t)UiTextStyle.sample9] = &fontSmall;
    layoutContext.fonts[cast(size_t)UiTextStyle.sample11] = &fontMedium;
    layoutContext.fonts[cast(size_t)UiTextStyle.sampleMono] = &fontSmall;
    return layoutContext;
}

/** Builds the retained STATUS HUD window for the current frame. */
private UiWindow buildStatusWindow(HudWindowRect rect, ref HudLayoutState layoutState, float fps, float yawAngle, float pitchAngle, string shapeName, string renderModeName, string buildVersion, string platformName, uint vulkanApiVersion, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont)
{
    const titleText = "Status";
    const metrics = measureStatusWindow(fps, yawAngle, pitchAngle, shapeName, renderModeName, buildVersion, platformName, vulkanApiVersion, mediumFont);
    const rowLabels = ["Platform:", "Vulkan API:", "Frame Rate:", "Camera Yaw:", "Camera Pitch:", "Active Shape:", "Current Mode:", "Build:"];
    const rowValues = [
        platformName,
        format("%u.%u.%u", cast(uint)(vulkanApiVersion >> 22), cast(uint)((vulkanApiVersion >> 12) & 0x3ff), cast(uint)(vulkanApiVersion & 0xfff)),
        format("%.0f FPS", fps),
        format("%.1f DEGREES", yawAngle * 180.0f / cast(float)PI),
        format("%.1f DEGREES", pitchAngle * 180.0f / cast(float)PI),
        shapeName,
        renderModeName,
        buildVersion,
    ];

    auto window = new UiWindow(titleText, rect.left, rect.top, rect.width, rect.height, cast(float[4])statusWindowBodyColor, cast(float[4])statusWindowHeaderColor, cast(float[4])statusWindowTitleColor, false, true, false);
    window.visible = layoutState.statusVisible;
    window.onClose = ()
    {
        logLine("UiWindow close: STATUS");
        layoutState.statusVisible = false;
    };

    auto content = new UiVBox(0.0f, 0.0f, max(rect.width - statusWindowInnerWidthPadding, 0.0f), max(rect.height - statusWindowInnerHeightPadding, 0.0f), metrics.rowSpacing);
    content.setLayoutHint(0.0f, metrics.contentHeight, metrics.contentWidth, metrics.contentHeight, float.max, metrics.contentHeight, 1.0f, 0.0f);

    UiLayoutContext layoutContext = buildLayoutContext(smallFont, mediumFont);

    foreach (index; 0 .. rowLabels.length)
    {
        auto row = new UiHBox(0.0f, 0.0f, 0.0f, metrics.rowHeight, 0.0f);
        row.setLayoutHint(0.0f, metrics.rowHeight, metrics.contentWidth, metrics.rowHeight, float.max, metrics.rowHeight, 1.0f, 0.0f);

        auto label = new UiLabel(cast(string)rowLabels[index], 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])statusWindowPlatformColor);
        row.add(label);

        auto spacer = new UiSpacer(statusWindowColumnGap, metrics.rowHeight);
        spacer.setLayoutHint(statusWindowColumnGap, metrics.rowHeight, statusWindowColumnGap, metrics.rowHeight, float.max, metrics.rowHeight, 1.0f, 0.0f);
        row.add(spacer);

        float[4] valueColor;
        switch (index)
        {
            case statusRowPlatform: valueColor = cast(float[4])statusWindowPlatformColor; break;
            case statusRowVulkan: valueColor = cast(float[4])statusWindowPlatformColor; break;
            case statusRowFrameRate: valueColor = cast(float[4])statusWindowBodyTextColor; break;
            case statusRowYaw: valueColor = cast(float[4])statusWindowYawColor; break;
            case statusRowPitch: valueColor = cast(float[4])statusWindowPitchColor; break;
            case statusRowShape: valueColor = cast(float[4])statusWindowBodyTextColor; break;
            case statusRowMode: valueColor = cast(float[4])statusWindowModeColor; break;
            case statusRowBuild: valueColor = cast(float[4])statusWindowBuildColor; break;
            default: valueColor = cast(float[4])statusWindowBodyTextColor; break;
        }

        auto value = new UiLabel(cast(string)rowValues[index], 0.0f, 0.0f, UiTextStyle.medium, valueColor);
        row.add(value);
        content.add(row);
    }

    content.layout(layoutContext);
    window.add(content);
    return window;
}

/** Builds the retained render-mode control window.
 *
 * Params:
 *   rect = Final window rectangle in pixels.
 *   mediumFont = Font atlas used to size the mode buttons.
 *   onFlatColor = Callback for the flat-color render mode button.
 *   onLitTextured = Callback for the lit/textured render mode button.
 *   onWireframe = Callback for the wireframe render mode button.
 *   onHiddenLine = Callback for the hidden-line render mode button.
 *   onPreviousShape = Callback for the previous-shape button.
 *   onNextShape = Callback for the next-shape button.
 *   onSettings = Callback for the settings button.
 *   onToggleStatus = Callback for the status-window toggle button.
 *   onToggleSample = Callback for the sample-window toggle button.
 *   onToggleInput = Callback for the input-window toggle button.
 *   onToggleCenter = Callback for the center-window toggle button.
 *
 * Returns:
 *   A retained window tree for the render-mode buttons.
 */
private UiWindow buildModeWindow(HudWindowRect rect, ref const(FontAtlas) mediumFont, void delegate() onFlatColor = null, void delegate() onLitTextured = null, void delegate() onWireframe = null, void delegate() onHiddenLine = null, void delegate() onPreviousShape = null, void delegate() onNextShape = null, void delegate() onSettings = null, void delegate() onToggleStatus = null, void delegate() onToggleSample = null, void delegate() onToggleInput = null, void delegate() onToggleCenter = null)
{
    const mediumTextHeight = textBlockHeight(mediumFont);
    const buttonHeight = max(mediumTextHeight + 14.0f, 28.0f);

    auto window = new UiWindow("Render Modes", rect.left, rect.top, rect.width, rect.height, [0.10f, 0.12f, 0.16f, 0.94f], [0.14f, 0.16f, 0.20f, 0.96f], [1.00f, 0.98f, 0.82f, 1.00f], false, false, false, 6.0f, 6.0f, 6.0f, 6.0f);
    auto content = new UiVBox(0.0f, 0.0f, max(rect.width - 22.0f, 0.0f), max(rect.height - 22.0f, 0.0f));
    UiLayoutContext layoutContext = buildLayoutContext(mediumFont, mediumFont);

    auto modeSection = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, 4.0f);
    auto topRow = new UiHBox(0.0f, 0.0f, 0.0f, buttonHeight, 4.0f);
    auto flatColorButton = new UiButton("F  Flat Color", 0.0f, 0.0f, 0.0f, 0.0f, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]);
    flatColorButton.onClick = onFlatColor;
    topRow.add(flatColorButton);
    auto litTexturedButton = new UiButton("T  Lit / Textured", 0.0f, 0.0f, 0.0f, 0.0f, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]);
    litTexturedButton.onClick = onLitTextured;
    topRow.add(litTexturedButton);
    modeSection.add(topRow);

    auto secondarySection = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, 4.0f);
    auto bottomRow = new UiHBox(0.0f, 0.0f, 0.0f, buttonHeight, 4.0f);
    auto wireframeButton = new UiButton("W  Wireframe", 0.0f, 0.0f, 0.0f, 0.0f, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]);
    wireframeButton.onClick = onWireframe;
    bottomRow.add(wireframeButton);
    auto hiddenLineButton = new UiButton("H  Hidden Line", 0.0f, 0.0f, 0.0f, 0.0f, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]);
    hiddenLineButton.onClick = onHiddenLine;
    bottomRow.add(hiddenLineButton);
    secondarySection.add(bottomRow);

    auto shapeSection = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, 4.0f);
    auto modelRow = new UiHBox(0.0f, 0.0f, 0.0f, buttonHeight, 4.0f);
    auto previousShapeButton = new UiButton("Model -", 0.0f, 0.0f, 0.0f, 0.0f, [0.14f, 0.16f, 0.22f, 0.96f], [0.18f, 0.46f, 0.82f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]);
    previousShapeButton.onClick = onPreviousShape;
    modelRow.add(previousShapeButton);
    auto nextShapeButton = new UiButton("Model +", 0.0f, 0.0f, 0.0f, 0.0f, [0.14f, 0.16f, 0.22f, 0.96f], [0.18f, 0.46f, 0.82f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]);
    nextShapeButton.onClick = onNextShape;
    modelRow.add(nextShapeButton);
    shapeSection.add(modelRow);

    auto windowSection = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, 4.0f);
    auto windowRow = new UiHBox(0.0f, 0.0f, 0.0f, buttonHeight, 4.0f);
    auto statusButton = new UiButton("Status", 0.0f, 0.0f, 0.0f, 0.0f, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]);
    statusButton.onClick = onToggleStatus;
    windowRow.add(statusButton);
    auto sampleButton = new UiButton("Sample", 0.0f, 0.0f, 0.0f, 0.0f, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]);
    sampleButton.onClick = onToggleSample;
    windowRow.add(sampleButton);
    windowSection.add(windowRow);

    auto logSection = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, 4.0f);
    auto secondWindowRow = new UiHBox(0.0f, 0.0f, 0.0f, buttonHeight, 4.0f);
    auto logButton = new UiButton("Log", 0.0f, 0.0f, 0.0f, 0.0f, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]);
    logButton.onClick = onToggleInput;
    secondWindowRow.add(logButton);
    auto settingsToggleButton = new UiButton("Settings", 0.0f, 0.0f, 0.0f, 0.0f, [0.18f, 0.20f, 0.28f, 0.96f], [0.32f, 0.72f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]);
    settingsToggleButton.onClick = onSettings;
    secondWindowRow.add(settingsToggleButton);
    logSection.add(secondWindowRow);

    auto centerSection = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, 4.0f);
    auto centerRow = new UiHBox(0.0f, 0.0f, 0.0f, buttonHeight, 4.0f);
    auto centerToggleButton = new UiButton("Drag Me", 0.0f, 0.0f, 0.0f, 0.0f, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]);
    centerToggleButton.onClick = onToggleCenter;
    centerRow.add(centerToggleButton);
    centerSection.add(centerRow);

    content.add(modeSection);
    content.add(new UiSpacer(0.0f, 3.0f));
    content.add(secondarySection);
    content.add(new UiSpacer(0.0f, 3.0f));
    content.add(shapeSection);
    content.add(new UiSpacer(0.0f, 3.0f));
    content.add(windowSection);
    content.add(new UiSpacer(0.0f, 3.0f));
    content.add(logSection);
    content.add(new UiSpacer(0.0f, 3.0f));
    content.add(centerSection);

    content.layout(layoutContext);

    window.add(content);
    return window;
}

private float measuredTextWidth(ref const(FontAtlas) font, string text)
{
    return textBlockWidth(font, text);
}

private float measuredTextHeight(ref const(FontAtlas) font)
{
    return textBlockHeight(font);
}

private float measuredButtonWidth(ref const(FontAtlas) font, string text, float padding)
{
    return measuredTextWidth(font, text) + padding;
}

private float measuredButtonHeight(ref const(FontAtlas) font, float padding, float minimumHeight)
{
    return max(measuredTextHeight(font) + padding, minimumHeight);
}

/** Builds the retained settings dialog window.
 *
 * Params:
 *   rect = Final window rectangle in pixels.
 *   layoutState = Persistent dialog placement and drag state.
 *   extentWidth = Swapchain width in pixels.
 *   extentHeight = Swapchain height in pixels.
 *   settingsDraft = Mutable draft settings edited by the dialog.
 *   onApplySettings = Callback invoked when Apply is pressed.
 *   smallFont = Font atlas used for smaller layout measurements.
 *   mediumFont = Font atlas used for labels and buttons.
 *
 * Returns:
 *   A retained settings window tree.
 */
private UiWindow buildSettingsWindow(HudWindowRect rect, ref HudLayoutState layoutState, float extentWidth, float extentHeight, ref DemoSettings settingsDraft, void delegate() onApplySettings, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont)
{
    float[4] labelColor = [1.00f, 1.00f, 1.00f, 1.00f];
    float[4] accentColor = [0.86f, 0.96f, 1.00f, 1.00f];
    float[4] buttonFill = [0.16f, 0.18f, 0.24f, 0.96f];
    float[4] buttonBorder = [0.20f, 0.56f, 0.98f, 1.00f];
    float buttonHeight = max(cast(float)mediumFont.lineHeight + 10.0f, 24.0f);
    float wideButton = max(110.0f, textBlockWidth(mediumFont, "Fullscreen"));
    float valueButton = max(80.0f, textBlockWidth(mediumFont, "1920 x 1080"));

    auto window = new UiWindow("Settings", rect.left, rect.top, rect.width, rect.height, [0.09f, 0.11f, 0.15f, 0.96f], [0.14f, 0.16f, 0.20f, 0.98f], [1.00f, 0.98f, 0.82f, 1.00f], false, true, true);
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
    UiLayoutContext layoutContext = buildLayoutContext(smallFont, mediumFont);

    auto displaySection = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, 4.0f);
    displaySection.add(new UiLabel("Video and Display", 0.0f, 0.0f, UiTextStyle.medium, accentColor, cast(float)mediumFont.lineHeight));

    auto displayRow = new UiHBox(0.0f, 0.0f, 0.0f, buttonHeight, 4.0f);
    auto windowedButton = new UiButton("Windowed", 0.0f, 0.0f, wideButton, buttonHeight, buttonFill, buttonBorder, labelColor);
    windowedButton.onClick = ()
    {
        settingsDraft.display.windowMode = "windowed";
        settingsDraft.display.fullscreen = false;
    };
    displayRow.add(windowedButton);
    auto fullscreenButton = new UiButton("Fullscreen", 0.0f, 0.0f, wideButton, buttonHeight, buttonFill, buttonBorder, labelColor);
    fullscreenButton.onClick = ()
    {
        settingsDraft.display.windowMode = "fullscreen";
        settingsDraft.display.fullscreen = true;
    };
    displayRow.add(fullscreenButton);
    auto vsyncButton = new UiButton(settingsDraft.display.vsync ? "VSync On" : "VSync Off", 0.0f, 0.0f, wideButton, buttonHeight, buttonFill, buttonBorder, labelColor);
    vsyncButton.onClick = ()
    {
        settingsDraft.display.vsync = !settingsDraft.display.vsync;
    };
    displayRow.add(vsyncButton);
    displaySection.add(displayRow);

    displaySection.add(new UiLabel(format("Resolution: %s x %s", settingsDraft.display.windowWidth, settingsDraft.display.windowHeight), 0.0f, 0.0f, UiTextStyle.medium, labelColor, cast(float)mediumFont.lineHeight));
    auto resolutionRow = new UiHBox(0.0f, 0.0f, 0.0f, buttonHeight, 4.0f);
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
    displaySection.add(resolutionRow);

    auto gameplaySection = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, 4.0f);
    gameplaySection.add(new UiLabel("Gameplay and Input", 0.0f, 0.0f, UiTextStyle.medium, accentColor, cast(float)mediumFont.lineHeight));
    auto gameplayRow = new UiHBox(0.0f, 0.0f, 0.0f, buttonHeight, 4.0f);
    auto flatButton = new UiButton("Flat Color", 0.0f, 0.0f, wideButton, buttonHeight, buttonFill, buttonBorder, labelColor);
    flatButton.onClick = () { settingsDraft.gameplay.startupRenderMode = "flatColor"; };
    gameplayRow.add(flatButton);
    auto litButton = new UiButton("Lit / Textured", 0.0f, 0.0f, wideButton, buttonHeight, buttonFill, buttonBorder, labelColor);
    litButton.onClick = () { settingsDraft.gameplay.startupRenderMode = "litTextured"; };
    gameplayRow.add(litButton);
    auto wireButton = new UiButton("Wireframe", 0.0f, 0.0f, wideButton, buttonHeight, buttonFill, buttonBorder, labelColor);
    wireButton.onClick = () { settingsDraft.gameplay.startupRenderMode = "wireframe"; };
    gameplayRow.add(wireButton);
    auto hiddenButton = new UiButton("Hidden Line", 0.0f, 0.0f, wideButton, buttonHeight, buttonFill, buttonBorder, labelColor);
    hiddenButton.onClick = () { settingsDraft.gameplay.startupRenderMode = "hiddenLine"; };
    gameplayRow.add(hiddenButton);
    gameplaySection.add(gameplayRow);

    auto audioSection = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, 4.0f);
    audioSection.add(new UiLabel("Audio and UI", 0.0f, 0.0f, UiTextStyle.medium, accentColor, cast(float)mediumFont.lineHeight));
    auto uiRow = new UiHBox(0.0f, 0.0f, 0.0f, buttonHeight, 4.0f);
    auto compactButton = new UiButton(settingsDraft.ui.compactWindows ? "Compact On" : "Compact Off", 0.0f, 0.0f, wideButton, buttonHeight, buttonFill, buttonBorder, labelColor);
    compactButton.onClick = () { settingsDraft.ui.compactWindows = !settingsDraft.ui.compactWindows; };
    uiRow.add(compactButton);
    auto fontDownButton = new UiButton("Font -", 0.0f, 0.0f, wideButton, buttonHeight, buttonFill, buttonBorder, labelColor);
    fontDownButton.onClick = () { settingsDraft.ui.fontScale = max(0.8f, settingsDraft.ui.fontScale - 0.1f); };
    uiRow.add(fontDownButton);
    auto fontUpButton = new UiButton("Font +", 0.0f, 0.0f, wideButton, buttonHeight, buttonFill, buttonBorder, labelColor);
    fontUpButton.onClick = () { settingsDraft.ui.fontScale = min(1.6f, settingsDraft.ui.fontScale + 0.1f); };
    uiRow.add(fontUpButton);
    audioSection.add(uiRow);

    auto actionSection = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, 4.0f);
    auto actionRow = new UiHBox(0.0f, 0.0f, 0.0f, buttonHeight, 4.0f);
    auto applyButton = new UiButton("Apply", 0.0f, 0.0f, wideButton, buttonHeight, [0.20f, 0.34f, 0.22f, 0.96f], [0.28f, 0.80f, 0.46f, 1.00f], labelColor);
    applyButton.onClick = ()
    {
        if (onApplySettings !is null)
            onApplySettings();
        layoutState.settingsVisible = false;
    };
    actionRow.add(applyButton);
    auto resetButton = new UiButton("Reset", 0.0f, 0.0f, wideButton, buttonHeight, [0.22f, 0.20f, 0.16f, 0.96f], [0.82f, 0.66f, 0.28f, 1.00f], labelColor);
    resetButton.onClick = ()
    {
        settingsDraft = DemoSettings.init;
    };
    actionRow.add(resetButton);
    auto closeButton = new UiButton("Close", 0.0f, 0.0f, wideButton, buttonHeight, [0.42f, 0.16f, 0.16f, 0.96f], [0.92f, 0.46f, 0.46f, 1.00f], labelColor);
    closeButton.onClick = ()
    {
        layoutState.settingsVisible = false;
    };
    actionRow.add(closeButton);
    actionSection.add(actionRow);

    content.add(displaySection);
    content.add(new UiSpacer(0.0f, 6.0f));
    content.add(gameplaySection);
    content.add(new UiSpacer(0.0f, 6.0f));
    content.add(audioSection);
    content.add(new UiSpacer(0.0f, 2.0f));
    content.add(actionSection);

    content.layout(layoutContext);

    window.add(content);
    return window;
}

/** Sends a pointer event to the settings dialog and reports whether it handled it. */
bool hudDispatchSettingsWindowPointer(float extentWidth, float extentHeight, ref HudLayoutState layoutState, ref DemoSettings settingsDraft, float mouseX, float mouseY, UiPointerEventKind kind, uint button, void delegate() onApplySettings, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont)
{
    auto window = buildSettingsWindow(buildSettingsRect(extentWidth, extentHeight, layoutState, mediumFont), layoutState, extentWidth, extentHeight, settingsDraft, onApplySettings, smallFont, mediumFont);
    UiPointerEvent event;
    event.kind = kind;
    event.x = mouseX;
    event.y = mouseY;
    event.button = button;
    return window.dispatchPointerEvent(event);
}

/** Sends a button-down event to the mode buttons and reports whether one handled it. */
bool hudDispatchModeButtonDown(HudWindowRect rect, float mouseX, float mouseY, ref const(FontAtlas) mediumFont, void delegate() onFlatColor, void delegate() onLitTextured, void delegate() onWireframe, void delegate() onHiddenLine, void delegate() onPreviousShape, void delegate() onNextShape, void delegate() onSettings, void delegate() onToggleStatus, void delegate() onToggleSample, void delegate() onToggleInput, void delegate() onToggleCenter)
{
    auto window = buildModeWindow(rect, mediumFont, onFlatColor, onLitTextured, onWireframe, onHiddenLine, onPreviousShape, onNextShape, onSettings, onToggleStatus, onToggleSample, onToggleInput, onToggleCenter);
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

/** Builds the retained font-sample window.
 *
 * Params:
 *   rect = Final window rectangle in pixels.
 *   fontAtlases = Font atlases indexed by sample text size.
 *
 * Returns:
 *   A retained sample window tree.
 */
private UiWindow buildSampleWindow(HudWindowRect rect, const(FontAtlas)[] fontAtlases)
{
    const sample7Width = textBlockWidth(fontAtlases[0], "7 px  The quick brown fox");
    const sample8Width = textBlockWidth(fontAtlases[1], "8 px  The quick brown fox");
    const sample9Width = textBlockWidth(fontAtlases[2], "9 px  The quick brown fox");
    const sample10Width = textBlockWidth(fontAtlases[3], "10 px The quick brown fox");
    const sample11Width = textBlockWidth(fontAtlases[4], "11 px The quick brown fox");
    const sample12Width = textBlockWidth(fontAtlases[5], "12 px The quick brown fox");
    const sampleMonoWidth = textBlockWidth(fontAtlases[6], "10 px Mono The quick brown fox");
    const contentWidth = max(max(sample7Width, sample8Width), max(max(sample9Width, sample10Width), max(max(sample11Width, sample12Width), sampleMonoWidth)));
    const width = contentWidth + 36.0f;
    const sample7TextHeight = textBlockHeight(fontAtlases[0]);
    const sample8TextHeight = textBlockHeight(fontAtlases[1]);
    const sample9TextHeight = textBlockHeight(fontAtlases[2]);
    const sample10TextHeight = textBlockHeight(fontAtlases[3]);
    const sample11TextHeight = textBlockHeight(fontAtlases[4]);
    const sample12TextHeight = textBlockHeight(fontAtlases[5]);
    const sampleMonoTextHeight = textBlockHeight(fontAtlases[6]);
    const contentBottom = max(max(max(max(max(max(
        0.0f + sample7TextHeight,
        4.0f + sample8TextHeight),
        8.0f + sample9TextHeight),
        12.0f + sample10TextHeight),
        16.0f + sample11TextHeight),
        20.0f + sample12TextHeight),
        24.0f + sampleMonoTextHeight);
    const height = 32.0f + contentBottom + 12.0f;

    auto window = new UiWindow("Font Sample", rect.left, rect.top, rect.width, rect.height, [0.10f, 0.12f, 0.16f, 0.94f], [0.14f, 0.16f, 0.20f, 0.96f], [1.00f, 0.98f, 0.82f, 1.00f]);
    auto content = new UiVBox(0.0f, 0.0f, max(rect.width - 28.0f, 0.0f), max(rect.height - 28.0f, 0.0f), 2.0f);
    UiLayoutContext layoutContext;
    layoutContext.fonts[cast(size_t)UiTextStyle.sample7] = &fontAtlases[0];
    layoutContext.fonts[cast(size_t)UiTextStyle.sample8] = &fontAtlases[1];
    layoutContext.fonts[cast(size_t)UiTextStyle.sample9] = &fontAtlases[2];
    layoutContext.fonts[cast(size_t)UiTextStyle.sample10] = &fontAtlases[3];
    layoutContext.fonts[cast(size_t)UiTextStyle.sample11] = &fontAtlases[4];
    layoutContext.fonts[cast(size_t)UiTextStyle.sample12] = &fontAtlases[5];
    layoutContext.fonts[cast(size_t)UiTextStyle.sampleMono] = &fontAtlases[6];

    auto sampleColumn = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, 2.0f);
    sampleColumn.add(new UiLabel("7 px  The quick brown fox", 0.0f, 0.0f, UiTextStyle.sample7, [1.00f, 1.00f, 1.00f, 1.00f], sample7TextHeight));
    sampleColumn.add(new UiLabel("8 px  The quick brown fox", 0.0f, 0.0f, UiTextStyle.sample8, [1.00f, 1.00f, 1.00f, 1.00f], sample8TextHeight));
    sampleColumn.add(new UiLabel("9 px  The quick brown fox", 0.0f, 0.0f, UiTextStyle.sample9, [1.00f, 1.00f, 1.00f, 1.00f], sample9TextHeight));
    sampleColumn.add(new UiLabel("10 px The quick brown fox", 0.0f, 0.0f, UiTextStyle.sample10, [1.00f, 1.00f, 1.00f, 1.00f], sample10TextHeight));
    sampleColumn.add(new UiLabel("11 px The quick brown fox", 0.0f, 0.0f, UiTextStyle.sample11, [1.00f, 1.00f, 1.00f, 1.00f], sample11TextHeight));
    sampleColumn.add(new UiLabel("12 px The quick brown fox", 0.0f, 0.0f, UiTextStyle.sample12, [1.00f, 1.00f, 1.00f, 1.00f], sample12TextHeight));
    sampleColumn.add(new UiLabel("10 px Mono The quick brown fox", 0.0f, 0.0f, UiTextStyle.sampleMono, [1.00f, 1.00f, 1.00f, 1.00f], sampleMonoTextHeight));
    content.add(sampleColumn);
    content.layout(layoutContext);
    window.add(content);
    return window;
}

/** Builds the retained log/input window.
 *
 * Params:
 *   rect = Final window rectangle in pixels.
 *   mediumFont = Font atlas used for the multiline text block.
 *
 * Returns:
 *   A retained log window tree.
 */
private UiWindow buildInputWindow(HudWindowRect rect, ref const(FontAtlas) mediumFont)
{
    auto window = new UiWindow("Log", rect.left, rect.top, rect.width, rect.height, [0.10f, 0.12f, 0.16f, 0.92f], [0.14f, 0.16f, 0.20f, 0.96f], [1.00f, 0.98f, 0.82f, 1.00f]);
    auto content = new UiVBox(0.0f, 0.0f, max(rect.width - 28.0f, 0.0f), max(rect.height - 28.0f, 0.0f), 6.0f);
    UiLayoutContext layoutContext = buildLayoutContext(mediumFont, mediumFont);

    auto headerSection = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, 2.0f);
    headerSection.add(new UiLabel("Input Window", 0.0f, 0.0f, UiTextStyle.medium, [1.00f, 0.98f, 0.82f, 1.00f], cast(float)mediumFont.lineHeight));
    headerSection.add(new UiLabel("Becomes a log window", 0.0f, 0.0f, UiTextStyle.small, [0.90f, 0.95f, 1.00f, 1.00f]));

    auto bodySection = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, 3.0f);
    bodySection.add(new UiTextBlock("- Future console target\n- Multi-line retained text\n- Event and diagnostics output\n- Ready for admin commands", 0.0f, 0.0f, UiTextStyle.medium, [1.00f, 1.00f, 1.00f, 1.00f], mediumFont.lineHeight * 6.0f));

    content.add(headerSection);
    content.add(new UiSpacer(0.0f, 6.0f));
    content.add(bodySection);
    content.layout(layoutContext);
    window.add(content);
    return window;
}

/** Builds the draggable center test window.
 *
 * Params:
 *   rect = Final window rectangle in pixels.
 *   layoutState = Persistent drag and resize state.
 *   extentWidth = Swapchain width in pixels.
 *   extentHeight = Swapchain height in pixels.
 *   smallFont = Font atlas used for small-body measurements.
 *   mediumFont = Font atlas used for labels and text blocks.
 *
 * Returns:
 *   A retained center-window tree.
 */
private UiWindow buildCenterWindow(HudWindowRect rect, ref HudLayoutState layoutState, float extentWidth, float extentHeight, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont)
{
    const buttonHeight = max(cast(float)mediumFont.lineHeight + 10.0f, 24.0f);
    const smallTextHeight = textBlockHeight(smallFont);
    const mediumTextHeight = textBlockHeight(mediumFont);

    auto window = new UiWindow("Zieh mich", rect.left, rect.top, rect.width, rect.height, [0.10f, 0.12f, 0.16f, 0.92f], [0.14f, 0.16f, 0.20f, 0.96f], [1.00f, 0.98f, 0.82f, 1.00f], true, true, true);
    window.visible = layoutState.centerVisible;
    window.onClose = ()
    {
        logLine("UiWindow close: Zieh mich");
        layoutState.centerVisible = false;
        layoutState.middleDragging = false;
        layoutState.middleResizing = false;
        layoutState.middleResizeHandle = UiResizeHandle.none;
    };
    auto content = new UiVBox(0.0f, 0.0f, max(rect.width - 28.0f, 0.0f), max(rect.height - 28.0f, 0.0f), 8.0f);

    auto headerRow = new UiHBox(0.0f, 0.0f, 0.0f, 0.0f, 8.0f);
    auto titleColumn = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, 2.0f);
    titleColumn.add(new UiLabel("Center Window", 0.0f, 0.0f, UiTextStyle.medium, [1.00f, 0.98f, 0.82f, 1.00f]));
    titleColumn.add(new UiLabel("Resize to watch the layout", 0.0f, 0.0f, UiTextStyle.small, [0.90f, 0.95f, 1.00f, 1.00f], smallTextHeight));
    headerRow.add(titleColumn);

    auto headerSpacer = new UiSpacer(16.0f, 0.0f);
    headerSpacer.setLayoutHint(16.0f, 0.0f, 16.0f, 0.0f, float.max, 0.0f, 1.0f, 0.0f);
    headerRow.add(headerSpacer);

    auto badgeColumn = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, 2.0f);
    badgeColumn.add(new UiLabel("Live Relayout", 0.0f, 0.0f, UiTextStyle.medium, [0.86f, 0.96f, 1.00f, 1.00f]));
    badgeColumn.add(new UiLabel("Recompute on resize", 0.0f, 0.0f, UiTextStyle.small, [0.90f, 0.95f, 1.00f, 1.00f], smallTextHeight));
    headerRow.add(badgeColumn);
    content.add(headerRow);

    auto bodySection = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, 8.0f);
    bodySection.setLayoutHint(0.0f, 0.0f, 0.0f, 0.0f, float.max, float.max, 1.0f, 1.0f);
    auto topStretch = new UiSpacer(0.0f, 0.0f);
    topStretch.setLayoutHint(0.0f, 0.0f, 0.0f, 0.0f, float.max, float.max, 0.0f, 1.0f);
    bodySection.add(topStretch);

    auto panelRow = new UiHBox(0.0f, 0.0f, 0.0f, 0.0f, 10.0f);

    auto leftPanel = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, 4.0f);
    leftPanel.add(new UiLabel("Left Panel", 0.0f, 0.0f, UiTextStyle.medium, [0.86f, 0.96f, 1.00f, 1.00f]));
    leftPanel.add(new UiLabel("Header Drag", 0.0f, 0.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f], smallTextHeight));
    leftPanel.add(new UiButton("Check", 0.0f, 0.0f, 0.0f, 0.0f, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]));
    panelRow.add(leftPanel);

    auto centerPanel = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, 4.0f);
    centerPanel.add(new UiLabel("Middle Panel", 0.0f, 0.0f, UiTextStyle.medium, [0.86f, 0.96f, 1.00f, 1.00f]));
    centerPanel.add(new UiLabel("Short labels", 0.0f, 0.0f, UiTextStyle.small, [0.90f, 0.95f, 1.00f, 1.00f]));
    centerPanel.add(new UiLabel("No overlap when shrinking", 0.0f, 0.0f, UiTextStyle.small, [0.90f, 0.95f, 1.00f, 1.00f]));
    centerPanel.add(new UiButton("Center Action", 0.0f, 0.0f, 0.0f, 0.0f, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]));
    panelRow.add(centerPanel);

    auto rightPanel = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, 4.0f);
    rightPanel.add(new UiLabel("Right Panel", 0.0f, 0.0f, UiTextStyle.medium, [0.86f, 0.96f, 1.00f, 1.00f]));
    rightPanel.add(new UiButton("Layout", 0.0f, 0.0f, 0.0f, 0.0f, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]));
    rightPanel.add(new UiButton("Test", 0.0f, 0.0f, 0.0f, 0.0f, [0.14f, 0.16f, 0.22f, 0.96f], [0.18f, 0.46f, 0.82f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]));
    panelRow.add(rightPanel);
    bodySection.add(panelRow);

    auto controlRow = new UiHBox(0.0f, 0.0f, 0.0f, buttonHeight, 6.0f);
    controlRow.add(new UiButton("Header = Drag", 0.0f, 0.0f, 0.0f, 0.0f, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]));
    auto controlSpacer = new UiSpacer(12.0f, 0.0f);
    controlSpacer.setLayoutHint(12.0f, 0.0f, 12.0f, 0.0f, float.max, 0.0f, 1.0f, 0.0f);
    controlRow.add(controlSpacer);
    controlRow.add(new UiButton("Corners = Resize", 0.0f, 0.0f, 0.0f, 0.0f, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]));
    bodySection.add(controlRow);

    auto footerRow = new UiHBox(0.0f, 0.0f, 0.0f, 0.0f, 6.0f);
    footerRow.add(new UiLabel("Watch the HBoxes spread", 0.0f, 0.0f, UiTextStyle.small, [0.90f, 0.95f, 1.00f, 1.00f], smallTextHeight));
    auto footerSpacer = new UiSpacer(12.0f, 0.0f);
    footerSpacer.setLayoutHint(12.0f, 0.0f, 12.0f, 0.0f, float.max, 0.0f, 1.0f, 0.0f);
    footerRow.add(footerSpacer);
    footerRow.add(new UiLabel("Relayout Test", 0.0f, 0.0f, UiTextStyle.small, [0.90f, 0.95f, 1.00f, 1.00f], smallTextHeight));
    bodySection.add(footerRow);

    auto bottomStretch = new UiSpacer(0.0f, 0.0f);
    bottomStretch.setLayoutHint(0.0f, 0.0f, 0.0f, 0.0f, float.max, float.max, 0.0f, 1.0f);
    bodySection.add(bottomStretch);

    content.add(bodySection);

    UiLayoutContext layoutContext = buildLayoutContext(smallFont, mediumFont);
    content.layout(layoutContext);
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
        setLayoutHint(width, height, width, height, width, height, 0.0f, 0.0f);
        return UiLayoutSize(width, height);
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
        const windowTitle = format("Layout Test #%u", serial);
        window = new UiWindow(windowTitle, 36.0f, 36.0f, 420.0f, 280.0f, [0.10f, 0.12f, 0.16f, 0.95f], [0.14f, 0.16f, 0.20f, 0.98f], [1.00f, 0.98f, 0.82f, 1.00f], true, true, true, 14.0f, 12.0f, 14.0f, 12.0f);

        content = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, 10.0f);
        auto topRow = new UiHBox(0.0f, 0.0f, 0.0f, 0.0f, 10.0f);
        topRow.add(new LayoutDemoProbeBox(88.0f, 42.0f, [0.17f, 0.20f, 0.28f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f]));
        topRow.add(new LayoutDemoProbeBox(120.0f, 58.0f, [0.14f, 0.24f, 0.20f, 0.96f], [0.34f, 0.82f, 0.46f, 1.00f]));
        topRow.add(new LayoutDemoProbeBox(66.0f, 74.0f, [0.24f, 0.16f, 0.20f, 0.96f], [0.92f, 0.46f, 0.46f, 1.00f]));

        auto middleRow = new UiHBox(0.0f, 0.0f, 0.0f, 0.0f, 10.0f);
        auto middleColumn = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, 10.0f);
        middleColumn.add(new LayoutDemoProbeBox(152.0f, 30.0f, [0.18f, 0.18f, 0.18f, 0.96f], [0.82f, 0.72f, 0.28f, 1.00f]));
        middleColumn.add(new LayoutDemoProbeBox(152.0f, 52.0f, [0.17f, 0.20f, 0.28f, 0.96f], [0.34f, 0.82f, 0.46f, 1.00f]));
        middleRow.add(middleColumn);
        middleRow.add(new LayoutDemoProbeBox(126.0f, 92.0f, [0.14f, 0.24f, 0.20f, 0.96f], [0.92f, 0.46f, 0.46f, 1.00f]));

        auto bottomRow = new UiHBox(0.0f, 0.0f, 0.0f, 0.0f, 10.0f);
        bottomRow.add(new LayoutDemoProbeBox(72.0f, 40.0f, [0.24f, 0.16f, 0.20f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f]));
        bottomRow.add(new LayoutDemoProbeBox(164.0f, 40.0f, [0.18f, 0.18f, 0.18f, 0.96f], [0.34f, 0.82f, 0.46f, 1.00f]));
        bottomRow.add(new LayoutDemoProbeBox(92.0f, 40.0f, [0.17f, 0.20f, 0.28f, 0.96f], [0.82f, 0.72f, 0.28f, 1.00f]));

        content.add(new UiSpacer(12.0f, 6.0f));
        content.add(topRow);
        content.add(new UiSpacer(12.0f, 6.0f));
        content.add(middleRow);
        content.add(new UiSpacer(12.0f, 6.0f));
        content.add(bottomRow);

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

HudWindowRect buildSettingsRect(float extentWidth, float extentHeight, ref HudLayoutState layoutState, ref const(FontAtlas) mediumFont)
{
    const buttonHeight = measuredButtonHeight(mediumFont, 18.0f, 30.0f);
    const wideButton = measuredButtonWidth(mediumFont, "Compact Off", 30.0f);
    const valueButton = measuredButtonWidth(mediumFont, "1920 x 1080", 30.0f);
    const width = 52.0f + max(max(3.0f * wideButton + 8.0f, 36.0f + valueButton * 2.0f + 8.0f), max(4.0f * wideButton + 12.0f, 3.0f * wideButton + 8.0f));
    const height = 54.0f + measuredTextHeight(mediumFont) * 4.0f + buttonHeight * 5.0f + 96.0f;

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

private HudWindowRect buildStatusRect(float extentWidth, float extentHeight, float fps, float yawAngle, float pitchAngle, string shapeName, string renderModeName, string buildVersion, string platformName, uint vulkanApiVersion, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont)
{
    const metrics = measureStatusWindow(fps, yawAngle, pitchAngle, shapeName, renderModeName, buildVersion, platformName, vulkanApiVersion, mediumFont);
    const titleWidth = textBlockWidth(mediumFont, "Status");
    const width = max(titleWidth + statusWindowTitlePaddingX, metrics.contentWidth + statusWindowContentPaddingX);
    const height = statusWindowTitleHeight + metrics.contentHeight + statusWindowFooterPadding;
    return HudWindowRect(statusWindowMargin, statusWindowMargin, width, height);
}

private HudWindowRect buildModesRect(float extentWidth, float extentHeight, ref const(FontAtlas) mediumFont)
{
    const buttonLabels = ["F  Flat Color", "T  Lit / Textured", "W  Wireframe", "H  Hidden Line", "Model -", "Model +", "Status", "Sample", "Log", "Settings"];
    const buttonPadding = 18.0f;
    float buttonWidth = 0.0f;
    foreach (label; buttonLabels)
        buttonWidth = max(buttonWidth, textBlockWidth(mediumFont, label));
    buttonWidth += buttonPadding;

    const buttonRowWidth = buttonWidth * 2.0f + 4.0f;
    const width = buttonRowWidth + 32.0f;
    const mediumTextHeight = textBlockHeight(mediumFont);
    const buttonHeight = max(mediumTextHeight + 14.0f, 28.0f);
    const height = 32.0f + (buttonHeight * 5.0f + 12.0f) + 16.0f;
    return HudWindowRect(max(18.0f, extentWidth - 18.0f - width), 18.0f, width, height);
}

private HudWindowRect buildSampleRect(float extentWidth, float extentHeight, const(FontAtlas)[] fontAtlases)
{
    const sample7Width = textBlockWidth(fontAtlases[0], "7 PX  THE QUICK BROWN FOX");
    const sample8Width = textBlockWidth(fontAtlases[1], "8 PX  THE QUICK BROWN FOX");
    const sample9Width = textBlockWidth(fontAtlases[2], "9 PX  THE QUICK BROWN FOX");
    const sample10Width = textBlockWidth(fontAtlases[3], "10 PX THE QUICK BROWN FOX");
    const sample11Width = textBlockWidth(fontAtlases[4], "11 PX THE QUICK BROWN FOX");
    const sample12Width = textBlockWidth(fontAtlases[5], "12 PX THE QUICK BROWN FOX");
    const sampleMonoWidth = textBlockWidth(fontAtlases[6], "10 PX MONO THE QUICK BROWN FOX");
    const contentWidth = max(max(sample7Width, sample8Width), max(max(sample9Width, sample10Width), max(max(sample11Width, sample12Width), sampleMonoWidth)));
    const width = contentWidth + 36.0f;
    const sample7TextHeight = textBlockHeight(fontAtlases[0]);
    const sample8TextHeight = textBlockHeight(fontAtlases[1]);
    const sample9TextHeight = textBlockHeight(fontAtlases[2]);
    const sample10TextHeight = textBlockHeight(fontAtlases[3]);
    const sample11TextHeight = textBlockHeight(fontAtlases[4]);
    const sample12TextHeight = textBlockHeight(fontAtlases[5]);
    const monoTextHeight = textBlockHeight(fontAtlases[6]);
    const contentHeight = sample7TextHeight * 3.0f + sample8TextHeight * 0.0f + sample9TextHeight * 2.0f + sample10TextHeight * 2.0f + sample11TextHeight * 1.0f + sample12TextHeight * 1.0f + monoTextHeight + 2.0f * 6.0f;
    const height = 32.0f + contentHeight + 16.0f;
    return HudWindowRect(18.0f, max(18.0f, extentHeight - 18.0f - height), width, height);
}

private HudWindowRect buildInputRect(float extentWidth, float extentHeight, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont)
{
    const titleWidth = textBlockWidth(mediumFont, "LOG");
    const lineOne = textBlockWidth(mediumFont, "INPUT WINDOW BECOMES A LOG WINDOW.");
    const lineTwo = textBlockWidth(mediumFont, "FUTURE ADMIN CONSOLE / MULTILINE TEXT BASE.");
    const lineThree = textBlockWidth(mediumFont, "EVENTS, DIAGNOSTICS, COMMANDS, AND NOTES.");
    const contentWidth = max(max(lineOne, lineTwo), lineThree);
    const width = max(titleWidth + 28.0f, contentWidth + 40.0f);
    const smallTextHeight = textBlockHeight(mediumFont);
    const mediumTextHeight = textBlockHeight(mediumFont);
    const height = 36.0f + max(max(0.0f + mediumTextHeight, mediumTextHeight * 2.0f + 12.0f), mediumTextHeight * 6.0f + 28.0f) + 20.0f;
    return HudWindowRect(max(18.0f, extentWidth - 18.0f - width), max(18.0f, extentHeight - 18.0f - height), width, height);
}

private HudWindowRect buildCenterRect(float extentWidth, float extentHeight, ref HudLayoutState layoutState, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont)
{
    const titleWidth = textBlockWidth(mediumFont, "Center Window");
    const titleSubWidth = textBlockWidth(smallFont, "Resize to watch the layout");
    const badgeWidth = max(textBlockWidth(mediumFont, "Live Relayout"), textBlockWidth(smallFont, "Recompute on resize"));
    const headerWidth = max(titleWidth, titleSubWidth) + 16.0f + badgeWidth;
    const centerButtonHeight = max(cast(float)mediumFont.lineHeight + 10.0f, 24.0f);

    const leftPanelWidth = max(max(textBlockWidth(mediumFont, "Left Panel"), textBlockWidth(smallFont, "Header Drag")), measuredButtonWidth(mediumFont, "Check", 20.0f));
    const centerPanelWidth = max(max(max(textBlockWidth(mediumFont, "Middle Panel"), textBlockWidth(smallFont, "Short labels")), textBlockWidth(smallFont, "No overlap when shrinking")), measuredButtonWidth(mediumFont, "Center Action", 20.0f));
    const rightPanelWidth = max(max(textBlockWidth(mediumFont, "Right Panel"), measuredButtonWidth(mediumFont, "Layout", 20.0f)), measuredButtonWidth(mediumFont, "Test", 20.0f));
    const panelWidth = leftPanelWidth + 20.0f + centerPanelWidth + 20.0f + rightPanelWidth;

    const controlWidth = measuredButtonWidth(mediumFont, "Header = Drag", 20.0f) + 12.0f + measuredButtonWidth(mediumFont, "Corners = Resize", 20.0f);
    const footerWidth = max(textBlockWidth(smallFont, "Watch the HBoxes spread"), textBlockWidth(smallFont, "Relayout Test"));

    const contentWidth = max(max(headerWidth, panelWidth), max(controlWidth, footerWidth));
    const measuredWidth = contentWidth + 40.0f;
    const mediumTextHeight = measuredTextHeight(mediumFont);
    const smallTextHeight = measuredTextHeight(smallFont);
    const headerHeight = max(mediumTextHeight * 2.0f, smallTextHeight * 2.0f);
    const panelHeight = max(centerButtonHeight * 2.0f, mediumTextHeight * 4.0f + 12.0f);
    const footerHeight = max(smallTextHeight, mediumTextHeight);
    const measuredHeight = 32.0f + headerHeight + 12.0f + panelHeight + 12.0f + centerButtonHeight + 12.0f + footerHeight + 16.0f;

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
    return measureTextWidth(atlas, text);
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
