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
import std.algorithm : max;
import std.math : PI;

import vulkan.font : FontAtlas;
import vulkan.pipeline : Vertex;
import vulkan.ui.ui_event : UiPointerEvent, UiPointerEventKind, UiResizeHandle;
import vulkan.ui.ui_context : UiRenderContext, UiTextStyle;
import vulkan.ui.ui_button : UiButton;
import vulkan.ui.ui_container : UiContainer;
import vulkan.ui.ui_label : UiLabel;
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
    /** Whether the center window is currently shown. */
    bool centerVisible = true;
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
    /** Start index for small text vertices. */
    uint smallTextStart;
    /** Vertex count for small text geometry. */
    uint smallTextCount;
    /** Start index for medium text vertices. */
    uint mediumTextStart;
    /** Vertex count for medium text geometry. */
    uint mediumTextCount;
    /** Start index for large text vertices. */
    uint largeTextStart;
    /** Vertex count for large text geometry. */
    uint largeTextCount;
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
    /** Small-body text quads. */
    Vertex[] smallText;
    /** Medium-body text quads. */
    Vertex[] mediumText;
    /** Large sample text quads. */
    Vertex[] largeText;
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
HudOverlayGeometry buildHudOverlayVertices(float extentWidth, float extentHeight, float fps, float yawAngle, float pitchAngle, string shapeName, string renderModeName, ref HudLayoutState layoutState, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont, ref const(FontAtlas) largeFont)
{
    HudOverlayGeometry geometry;

    const layout = buildHudLayout(extentWidth, extentHeight, fps, yawAngle, pitchAngle, shapeName, renderModeName, layoutState, smallFont, mediumFont, largeFont);
    UiWindow[5] windows = [
           buildStatusWindow(layout.status, layoutState, fps, yawAngle, pitchAngle, shapeName, renderModeName, smallFont, mediumFont),
        buildModeWindow(layout.modes, smallFont),
        buildSampleWindow(layout.sample, smallFont, mediumFont, largeFont),
        buildInputWindow(layout.input, smallFont),
        buildCenterWindow(layout.center, layoutState, extentWidth, extentHeight, smallFont, mediumFont),
    ];

    foreach (index, window; windows)
    {
        Vertex[] windowPanels;
        Vertex[] windowSmallText;
        Vertex[] windowMediumText;
        Vertex[] windowLargeText;

        UiRenderContext context = UiRenderContext.init;
        context.extentWidth = extentWidth;
        context.extentHeight = extentHeight;
        context.originX = 0.0f;
        context.originY = 0.0f;
        context.depthBase = 0.10f - cast(float)index * 0.02f;
        context.smallFont = &smallFont;
        context.mediumFont = &mediumFont;
        context.largeFont = &largeFont;
        context.panels = &windowPanels;
        context.smallText = &windowSmallText;
        context.mediumText = &windowMediumText;
        context.largeText = &windowLargeText;

        window.render(context);

        HudWindowDrawRange range;
        range.panelsStart = cast(uint)geometry.panels.length;
        range.panelsCount = cast(uint)windowPanels.length;
        range.smallTextStart = cast(uint)geometry.smallText.length;
        range.smallTextCount = cast(uint)windowSmallText.length;
        range.mediumTextStart = cast(uint)geometry.mediumText.length;
        range.mediumTextCount = cast(uint)windowMediumText.length;
        range.largeTextStart = cast(uint)geometry.largeText.length;
        range.largeTextCount = cast(uint)windowLargeText.length;
        geometry.windows ~= range;

        geometry.panels ~= windowPanels;
        geometry.smallText ~= windowSmallText;
        geometry.mediumText ~= windowMediumText;
        geometry.largeText ~= windowLargeText;
    }

    return geometry;
}

/** Builds the pixel layout for all HUD windows.
 *
 * This layout is shared by hit testing, dragging, and rendering so the HUD
 * stays consistent across the input and draw paths.
 */
HudLayout buildHudLayout(float extentWidth, float extentHeight, float fps, float yawAngle, float pitchAngle, string shapeName, string renderModeName, ref HudLayoutState layoutState, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont, ref const(FontAtlas) largeFont)
{
    HudLayout layout;
    layout.status = buildStatusRect(extentWidth, extentHeight, fps, yawAngle, pitchAngle, shapeName, renderModeName, smallFont, mediumFont);
    layout.modes = buildModesRect(extentWidth, extentHeight, smallFont);
    layout.sample = buildSampleRect(extentWidth, extentHeight, smallFont, mediumFont, largeFont);
    layout.input = buildInputRect(extentWidth, extentHeight, smallFont, mediumFont);
    layout.center = buildCenterRect(extentWidth, extentHeight, layoutState, smallFont, mediumFont);
    return layout;
}

private UiWindow buildStatusWindow(HudWindowRect rect, ref HudLayoutState layoutState, float fps, float yawAngle, float pitchAngle, string shapeName, string renderModeName, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont)
{
    const titleText = "DESKTOP OVERLAY";
    const firstBodyWidth = textBlockWidth(smallFont, "NATIVE WINDOW PIXELS. REAL FONTS AT 12/18/24 PX.");
    const secondBodyWidth = textBlockWidth(mediumFont, format("FRAME RATE: %.0f FPS", fps));
    const thirdBodyWidth = textBlockWidth(smallFont, format("CAMERA YAW: %.1f DEGREES", yawAngle * 180.0f / cast(float)PI));
    const fourthBodyWidth = textBlockWidth(smallFont, format("CAMERA PITCH: %.1f DEGREES", pitchAngle * 180.0f / cast(float)PI));
    const fifthBodyWidth = textBlockWidth(smallFont, format("ACTIVE SHAPE: %s", shapeName));
    const sixthBodyWidth = textBlockWidth(smallFont, format("CURRENT MODE: %s", renderModeName));
    const contentWidth = max(max(max(max(firstBodyWidth, secondBodyWidth), max(thirdBodyWidth, fourthBodyWidth)), fifthBodyWidth), sixthBodyWidth);
    const titleWidth = textBlockWidth(mediumFont, titleText);
    const width = max(titleWidth + 24.0f, contentWidth + 36.0f);
    const smallTextHeight = textBlockHeight(smallFont);
    const mediumTextHeight = textBlockHeight(mediumFont);
    const contentBottom = max(
        max(max(max(max(
            smallTextHeight,
            34.0f + mediumTextHeight),
            68.0f + smallTextHeight),
            90.0f + smallTextHeight),
            114.0f + smallTextHeight),
        136.0f + smallTextHeight);
    const height = 36.0f + contentBottom + 20.0f;
    auto window = new UiWindow(titleText, rect.left, rect.top, rect.width, rect.height, [0.10f, 0.12f, 0.16f, 0.96f], [0.14f, 0.16f, 0.20f, 0.96f], [1.00f, 0.98f, 0.82f, 1.00f], false, true, false);
    window.visible = layoutState.statusVisible;
    window.onClose = ()
    {
        logLine("UiWindow close: DESKTOP OVERLAY");
        layoutState.statusVisible = false;
    };
    auto content = new UiVBox(0.0f, 0.0f, max(rect.width - 36.0f, 0.0f), max(rect.height - 36.0f, 0.0f));
    content.add(new UiLabel("NATIVE WINDOW PIXELS. REAL FONTS AT 12/18/24 PX.", 0.0f, 0.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f], smallTextHeight));
    content.add(new UiSpacer(0.0f, 22.0f));
    content.add(new UiLabel(format("FRAME RATE: %.0f FPS", fps), 0.0f, 0.0f, UiTextStyle.medium, [1.00f, 1.00f, 1.00f, 1.00f], mediumTextHeight));
    content.add(new UiSpacer(0.0f, 16.0f));
    content.add(new UiLabel(format("CAMERA YAW: %.1f DEGREES", yawAngle * 180.0f / cast(float)PI), 0.0f, 0.0f, UiTextStyle.small, [0.40f, 1.00f, 0.70f, 1.00f], smallTextHeight));
    content.add(new UiSpacer(0.0f, 10.0f));
    content.add(new UiLabel(format("CAMERA PITCH: %.1f DEGREES", pitchAngle * 180.0f / cast(float)PI), 0.0f, 0.0f, UiTextStyle.small, [0.50f, 0.86f, 1.00f, 1.00f], smallTextHeight));
    content.add(new UiSpacer(0.0f, 12.0f));
    content.add(new UiLabel(format("ACTIVE SHAPE: %s", shapeName), 0.0f, 0.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f], smallTextHeight));
    content.add(new UiSpacer(0.0f, 10.0f));
    content.add(new UiLabel(format("CURRENT MODE: %s", renderModeName), 0.0f, 0.0f, UiTextStyle.small, [1.00f, 0.90f, 0.45f, 1.00f], smallTextHeight));
    window.add(content);
    return window;
}

private UiWindow buildModeWindow(HudWindowRect rect, ref const(FontAtlas) smallFont, void delegate() onFlatColor = null, void delegate() onLitTextured = null, void delegate() onWireframe = null, void delegate() onHiddenLine = null)
{
    const buttonLabels = ["F  FLAT COLOR", "T  LIT / TEXTURED", "W  WIREFRAME", "H  HIDDEN LINE"];
    const actionLabels = ["+ / -  SWITCH SHAPE", "ARROWS  ROTATE CAMERA", "ESC  CLOSE APPLICATION"];
    const buttonPadding = 20.0f;

    float buttonWidth = 0.0f;
    foreach (label; buttonLabels)
        buttonWidth = max(buttonWidth, textBlockWidth(smallFont, label));
    buttonWidth += buttonPadding;

    float actionWidth = 0.0f;
    foreach (label; actionLabels)
        actionWidth = max(actionWidth, textBlockWidth(smallFont, label));

    const buttonRowWidth = buttonWidth * 2.0f + 4.0f;
    const contentWidth = max(buttonRowWidth, actionWidth);
    const width = contentWidth + 36.0f;
    const smallTextHeight = textBlockHeight(smallFont);
    const buttonHeight = max(smallTextHeight + 10.0f, 24.0f);
    const height = 36.0f + (buttonHeight * 2.0f + 4.0f + 12.0f + smallTextHeight * 3.0f + 24.0f) + 20.0f;

    auto window = new UiWindow("RENDER MODES", rect.left, rect.top, rect.width, rect.height, [0.10f, 0.12f, 0.16f, 0.94f], [0.14f, 0.16f, 0.20f, 0.96f], [1.00f, 0.98f, 0.82f, 1.00f]);
    auto content = new UiVBox(0.0f, 0.0f, max(rect.width - 36.0f, 0.0f), max(rect.height - 36.0f, 0.0f));

    auto topRow = new UiHBox(0.0f, 0.0f, buttonRowWidth, buttonHeight, 4.0f);
    auto flatColorButton = new UiButton("F  FLAT COLOR", 0.0f, 0.0f, buttonWidth, buttonHeight, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]);
    flatColorButton.onClick = onFlatColor;
    topRow.add(flatColorButton);
    auto litTexturedButton = new UiButton("T  LIT / TEXTURED", 0.0f, 0.0f, buttonWidth, buttonHeight, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]);
    litTexturedButton.onClick = onLitTextured;
    topRow.add(litTexturedButton);
    content.add(topRow);
    content.add(new UiSpacer(0.0f, 4.0f));

    auto bottomRow = new UiHBox(0.0f, 0.0f, buttonRowWidth, buttonHeight, 4.0f);
    auto wireframeButton = new UiButton("W  WIREFRAME", 0.0f, 0.0f, buttonWidth, buttonHeight, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]);
    wireframeButton.onClick = onWireframe;
    bottomRow.add(wireframeButton);
    auto hiddenLineButton = new UiButton("H  HIDDEN LINE", 0.0f, 0.0f, buttonWidth, buttonHeight, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]);
    hiddenLineButton.onClick = onHiddenLine;
    bottomRow.add(hiddenLineButton);
    content.add(bottomRow);

    content.add(new UiSpacer(0.0f, 12.0f));
    content.add(new UiLabel("+ / -  SWITCH SHAPE", 0.0f, 0.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f], smallTextHeight));
    content.add(new UiSpacer(0.0f, 12.0f));
    content.add(new UiLabel("ARROWS  ROTATE CAMERA", 0.0f, 0.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f], smallTextHeight));
    content.add(new UiSpacer(0.0f, 12.0f));
    content.add(new UiLabel("ESC  CLOSE APPLICATION", 0.0f, 0.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f], smallTextHeight));
    window.add(content);
    return window;
}

/** Sends a button-down event to the mode buttons and reports whether one handled it. */
bool hudDispatchModeButtonDown(HudWindowRect rect, float mouseX, float mouseY, ref const(FontAtlas) smallFont, void delegate() onFlatColor, void delegate() onLitTextured, void delegate() onWireframe, void delegate() onHiddenLine)
{
    auto window = buildModeWindow(rect, smallFont, onFlatColor, onLitTextured, onWireframe, onHiddenLine);
    UiPointerEvent event;
    event.kind = UiPointerEventKind.buttonDown;
    event.x = mouseX;
    event.y = mouseY;
    event.button = 1;
    return window.dispatchPointerEvent(event);
}

private UiWindow buildSampleWindow(HudWindowRect rect, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont, ref const(FontAtlas) largeFont)
{
    const sampleSmall = textBlockWidth(smallFont, "12 PX  THE QUICK BROWN FOX");
    const sampleMedium = textBlockWidth(mediumFont, "18 PX  THE QUICK BROWN FOX");
    const sampleLarge = textBlockWidth(largeFont, "24 PX  THE QUICK BROWN FOX");
    const sampleFooter = textBlockWidth(smallFont, "REAL FONTS KEEP SIZES DISTINCT.");
    const contentWidth = max(max(sampleSmall, sampleMedium), max(sampleLarge, sampleFooter));
    const width = contentWidth + 36.0f;
    const smallTextHeight = textBlockHeight(smallFont);
    const mediumTextHeight = textBlockHeight(mediumFont);
    const largeTextHeight = textBlockHeight(largeFont);
    const contentBottom = max(
        max(max(
            0.0f + smallTextHeight,
            32.0f + mediumTextHeight),
            74.0f + largeTextHeight),
        124.0f + smallTextHeight);
    const height = 36.0f + contentBottom + 20.0f;

    auto window = new UiWindow("FONT SIZES", rect.left, rect.top, rect.width, rect.height, [0.10f, 0.12f, 0.16f, 0.94f], [0.14f, 0.16f, 0.20f, 0.96f], [1.00f, 0.98f, 0.82f, 1.00f]);
    auto content = new UiVBox(0.0f, 0.0f, max(rect.width - 36.0f, 0.0f), max(rect.height - 36.0f, 0.0f));
    content.add(new UiLabel("12 PX  THE QUICK BROWN FOX", 0.0f, 0.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f], smallTextHeight));
    content.add(new UiSpacer(0.0f, 20.0f));
    content.add(new UiLabel("18 PX  THE QUICK BROWN FOX", 0.0f, 0.0f, UiTextStyle.medium, [1.00f, 1.00f, 1.00f, 1.00f], mediumTextHeight));
    content.add(new UiSpacer(0.0f, 24.0f));
    content.add(new UiLabel("24 PX  THE QUICK BROWN FOX", 0.0f, 0.0f, UiTextStyle.large, [1.00f, 1.00f, 1.00f, 1.00f], largeTextHeight));
    content.add(new UiSpacer(0.0f, 26.0f));
    content.add(new UiLabel("REAL FONTS KEEP SIZES DISTINCT.", 0.0f, 0.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f], smallTextHeight));
    window.add(content);
    return window;
}

private UiWindow buildInputWindow(HudWindowRect rect, ref const(FontAtlas) smallFont)
{
    auto window = new UiWindow("INPUT", rect.left, rect.top, rect.width, rect.height, [0.10f, 0.12f, 0.16f, 0.92f], [0.14f, 0.16f, 0.20f, 0.96f], [1.00f, 0.98f, 0.82f, 1.00f]);
    auto content = new UiVBox(0.0f, 0.0f, max(rect.width - 36.0f, 0.0f), max(rect.height - 36.0f, 0.0f));
    content.add(new UiLabel("LEFT BUTTON DRAGS THE CENTER WINDOW.", 0.0f, 0.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f], smallFont.lineHeight));
    content.add(new UiSpacer(0.0f, 12.0f));
    content.add(new UiLabel("CLICK OUTSIDE THE UI TO ROTATE 3D.", 0.0f, 0.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f], smallFont.lineHeight));
    content.add(new UiSpacer(0.0f, 12.0f));
    content.add(new UiLabel("HEADER BAR IS THE DRAG HANDLE.", 0.0f, 0.0f, UiTextStyle.small, [0.90f, 0.95f, 1.00f, 1.00f], smallFont.lineHeight));
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
    };
    auto content = new UiVBox(0.0f, 0.0f, max(rect.width - 36.0f, 0.0f), max(rect.height - 36.0f, 0.0f));
    content.add(new UiLabel("GRAB THE BLUE BAR TO MOVE THIS WINDOW.", 0.0f, 0.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f], smallFont.lineHeight));
    content.add(new UiSpacer(0.0f, 12.0f));
    content.add(new UiLabel("UI HITS DO NOT FALL THROUGH TO 3D.", 0.0f, 0.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f], smallFont.lineHeight));
    content.add(new UiSpacer(0.0f, 12.0f));
    content.add(new UiLabel("OUTSIDE HITS GO TO THE OBJECT LAYER.", 0.0f, 0.0f, UiTextStyle.small, [0.90f, 0.95f, 1.00f, 1.00f], smallFont.lineHeight));
    content.add(new UiSpacer(0.0f, 12.0f));
    content.add(new UiLabel("DRAGGING USES THE HEADER BAR ONLY.", 0.0f, 0.0f, UiTextStyle.small, [0.90f, 0.95f, 1.00f, 1.00f], smallFont.lineHeight));
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

private HudWindowRect buildStatusRect(float extentWidth, float extentHeight, float fps, float yawAngle, float pitchAngle, string shapeName, string renderModeName, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont)
{
    const firstBodyWidth = textBlockWidth(smallFont, "NATIVE WINDOW PIXELS. REAL FONTS AT 12/18/24 PX.");
    const secondBodyWidth = textBlockWidth(mediumFont, format("FRAME RATE: %.0f FPS", fps));
    const thirdBodyWidth = textBlockWidth(smallFont, format("CAMERA YAW: %.1f DEGREES", yawAngle * 180.0f / cast(float)PI));
    const fourthBodyWidth = textBlockWidth(smallFont, format("CAMERA PITCH: %.1f DEGREES", pitchAngle * 180.0f / cast(float)PI));
    const fifthBodyWidth = textBlockWidth(smallFont, format("ACTIVE SHAPE: %s", shapeName));
    const sixthBodyWidth = textBlockWidth(smallFont, format("CURRENT MODE: %s", renderModeName));
    const contentWidth = max(max(max(max(firstBodyWidth, secondBodyWidth), max(thirdBodyWidth, fourthBodyWidth)), fifthBodyWidth), sixthBodyWidth);
    const titleWidth = textBlockWidth(mediumFont, "DESKTOP OVERLAY");
    const width = max(titleWidth + 24.0f, contentWidth + 36.0f);
    const smallTextHeight = textBlockHeight(smallFont);
    const mediumTextHeight = textBlockHeight(mediumFont);
    const contentBottom = max(max(max(max(max(smallTextHeight, 34.0f + mediumTextHeight), 68.0f + smallTextHeight), 90.0f + smallTextHeight), 114.0f + smallTextHeight), 136.0f + smallTextHeight);
    const height = 36.0f + contentBottom + 20.0f;
    return HudWindowRect(18.0f, 18.0f, width, height);
}

private HudWindowRect buildModesRect(float extentWidth, float extentHeight, ref const(FontAtlas) smallFont)
{
    const buttonLabels = ["F  FLAT COLOR", "T  LIT / TEXTURED", "W  WIREFRAME", "H  HIDDEN LINE"];
    const actionLabels = ["+ / -  SWITCH SHAPE", "ARROWS  ROTATE CAMERA", "ESC  CLOSE APPLICATION"];
    const buttonPadding = 20.0f;
    float buttonWidth = 0.0f;
    foreach (label; buttonLabels)
        buttonWidth = max(buttonWidth, textBlockWidth(smallFont, label));
    buttonWidth += buttonPadding;

    float actionWidth = 0.0f;
    foreach (label; actionLabels)
        actionWidth = max(actionWidth, textBlockWidth(smallFont, label));

    const buttonRowWidth = buttonWidth * 2.0f + 4.0f;
    const contentWidth = max(buttonRowWidth, actionWidth);
    const width = contentWidth + 36.0f;
    const smallTextHeight = textBlockHeight(smallFont);
    const buttonHeight = max(smallTextHeight + 10.0f, 24.0f);
    const contentBottom = max(max(max(max(0.0f + buttonHeight, (buttonHeight + 4.0f) + buttonHeight), (buttonHeight + 4.0f) * 2.0f + buttonHeight), (buttonHeight + 4.0f) * 3.0f + buttonHeight), 168.0f + smallTextHeight);
    const contentBottomWithLabels = max(contentBottom, max(120.0f + smallTextHeight, 144.0f + smallTextHeight));
    const height = 36.0f + contentBottomWithLabels + 20.0f;
    return HudWindowRect(max(18.0f, extentWidth - 18.0f - width), 18.0f, width, height);
}

private HudWindowRect buildSampleRect(float extentWidth, float extentHeight, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont, ref const(FontAtlas) largeFont)
{
    const sampleSmall = textBlockWidth(smallFont, "12 PX  THE QUICK BROWN FOX");
    const sampleMedium = textBlockWidth(mediumFont, "18 PX  THE QUICK BROWN FOX");
    const sampleLarge = textBlockWidth(largeFont, "24 PX  THE QUICK BROWN FOX");
    const sampleFooter = textBlockWidth(smallFont, "REAL FONTS KEEP SIZES DISTINCT.");
    const contentWidth = max(max(sampleSmall, sampleMedium), max(sampleLarge, sampleFooter));
    const width = contentWidth + 36.0f;
    const smallTextHeight = textBlockHeight(smallFont);
    const mediumTextHeight = textBlockHeight(mediumFont);
    const largeTextHeight = textBlockHeight(largeFont);
    const contentBottom = max(max(max(0.0f + smallTextHeight, 32.0f + mediumTextHeight), 74.0f + largeTextHeight), 124.0f + smallTextHeight);
    const height = 36.0f + contentBottom + 20.0f;
    return HudWindowRect(18.0f, max(18.0f, extentHeight - 18.0f - height), width, height);
}

private HudWindowRect buildInputRect(float extentWidth, float extentHeight, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont)
{
    const titleWidth = textBlockWidth(mediumFont, "INPUT");
    const lineOne = textBlockWidth(smallFont, "LEFT BUTTON DRAGS THE CENTER WINDOW.");
    const lineTwo = textBlockWidth(smallFont, "CLICK OUTSIDE THE UI TO ROTATE 3D.");
    const lineThree = textBlockWidth(smallFont, "HEADER BAR IS THE DRAG HANDLE.");
    const contentWidth = max(max(lineOne, lineTwo), lineThree);
    const width = max(titleWidth + 24.0f, contentWidth + 36.0f);
    const smallTextHeight = textBlockHeight(smallFont);
    const mediumTextHeight = textBlockHeight(mediumFont);
    const height = 36.0f + max(max(0.0f + smallTextHeight, smallTextHeight + 12.0f + smallTextHeight), smallTextHeight * 2.0f + 24.0f) + 20.0f;
    return HudWindowRect(max(18.0f, extentWidth - 18.0f - width), max(18.0f, extentHeight - 18.0f - height), width, height);
}

private HudWindowRect buildCenterRect(float extentWidth, float extentHeight, ref HudLayoutState layoutState, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont)
{
    const titleWidth = textBlockWidth(mediumFont, "DRAG ME");
    const lineOne = textBlockWidth(smallFont, "GRAB THE BLUE BAR TO MOVE THIS WINDOW.");
    const lineTwo = textBlockWidth(smallFont, "UI HITS DO NOT FALL THROUGH TO 3D.");
    const lineThree = textBlockWidth(smallFont, "OUTSIDE HITS GO TO THE OBJECT LAYER.");
    const lineFour = textBlockWidth(smallFont, "DRAGGING USES THE HEADER BAR ONLY.");
    const contentWidth = max(max(lineOne, lineTwo), max(lineThree, lineFour));
    const measuredWidth = max(titleWidth + 24.0f, contentWidth + 36.0f);
    const smallTextHeight = textBlockHeight(smallFont);
    const mediumTextHeight = textBlockHeight(mediumFont);
    const measuredHeight = 36.0f + max(max(max(0.0f + smallTextHeight, smallTextHeight + 12.0f + smallTextHeight), smallTextHeight * 2.0f + 24.0f), smallTextHeight * 3.0f + 36.0f) + 20.0f;

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
