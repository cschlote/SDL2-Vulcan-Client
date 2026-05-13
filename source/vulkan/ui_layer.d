/** $purposeofFile
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018
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
import vulkan.ui : UiButton, UiContainer, UiLabel, UiRenderContext, UiTextStyle, UiWindow;

/** Describes one HUD window rectangle in pixel coordinates. */
struct HudWindowRect
{
    float left;
    float top;
    float width;
    float height;
}

/** Tracks the draggable middle window and keeps it within the viewport. */
struct HudLayoutState
{
    float middleLeft;
    float middleTop;
    float middleWidth;
    float middleHeight;
    bool middleInitialized;
    bool middleDragging;
    float dragOffsetX;
    float dragOffsetY;
}

/** Pixel layout for all HUD windows. */
struct HudLayout
{
    HudWindowRect status;
    HudWindowRect modes;
    HudWindowRect sample;
    HudWindowRect input;
    HudWindowRect center;
}

/** Holds the panel and text geometry for the HUD overlay.
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
}

/** Builds the HUD overlay geometry for the current frame.
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

    auto root = new UiContainer();
    root.add(buildStatusWindow(layout.status, fps, yawAngle, pitchAngle, shapeName, renderModeName, smallFont, mediumFont));
    root.add(buildModeWindow(layout.modes, smallFont));
    root.add(buildSampleWindow(layout.sample, smallFont, mediumFont, largeFont));
    root.add(buildInputWindow(layout.input, smallFont));
    root.add(buildCenterWindow(layout.center, smallFont, mediumFont));

    UiRenderContext context = UiRenderContext.init;
    context.extentWidth = extentWidth;
    context.extentHeight = extentHeight;
    context.originX = 0.0f;
    context.originY = 0.0f;
    context.smallFont = &smallFont;
    context.mediumFont = &mediumFont;
    context.largeFont = &largeFont;
    context.panels = &geometry.panels;
    context.smallText = &geometry.smallText;
    context.mediumText = &geometry.mediumText;
    context.largeText = &geometry.largeText;

    root.render(context);

    return geometry;
}

/** Builds the pixel layout for all HUD windows. */
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

private UiWindow buildStatusWindow(HudWindowRect rect, float fps, float yawAngle, float pitchAngle, string shapeName, string renderModeName, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont)
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
    auto window = new UiWindow(titleText, rect.left, rect.top, rect.width, rect.height, [0.10f, 0.12f, 0.16f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 0.98f, 0.82f, 1.00f]);
    window.add(new UiLabel("NATIVE WINDOW PIXELS. REAL FONTS AT 12/18/24 PX.", 0.0f, 0.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiLabel(format("FRAME RATE: %.0f FPS", fps), 0.0f, 34.0f, UiTextStyle.medium, [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiLabel(format("CAMERA YAW: %.1f DEGREES", yawAngle * 180.0f / cast(float)PI), 0.0f, 68.0f, UiTextStyle.small, [0.40f, 1.00f, 0.70f, 1.00f]));
    window.add(new UiLabel(format("CAMERA PITCH: %.1f DEGREES", pitchAngle * 180.0f / cast(float)PI), 0.0f, 90.0f, UiTextStyle.small, [0.50f, 0.86f, 1.00f, 1.00f]));
    window.add(new UiLabel(format("ACTIVE SHAPE: %s", shapeName), 0.0f, 114.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiLabel(format("CURRENT MODE: %s", renderModeName), 0.0f, 136.0f, UiTextStyle.small, [1.00f, 0.90f, 0.45f, 1.00f]));
    return window;
}

private UiWindow buildModeWindow(HudWindowRect rect, ref const(FontAtlas) smallFont)
{
    const buttonLabels = [
        "F  FLAT COLOR",
        "T  LIT / TEXTURED",
        "W  WIREFRAME",
        "H  HIDDEN LINE",
    ];
    const actionLabels = [
        "+ / -  SWITCH SHAPE",
        "ARROWS  ROTATE CAMERA",
        "ESC  CLOSE APPLICATION",
    ];
    float contentWidth = 0.0f;
    foreach (label; buttonLabels)
        contentWidth = max(contentWidth, textBlockWidth(smallFont, label));
    foreach (label; actionLabels)
        contentWidth = max(contentWidth, textBlockWidth(smallFont, label));

    const width = contentWidth + 36.0f;
    const smallTextHeight = textBlockHeight(smallFont);
    const buttonHeight = max(smallTextHeight + 10.0f, 24.0f);
    const contentBottom = max(
        max(max(max(
            0.0f + buttonHeight,
            (buttonHeight + 4.0f) + buttonHeight),
            (buttonHeight + 4.0f) * 2.0f + buttonHeight),
            (buttonHeight + 4.0f) * 3.0f + buttonHeight),
        168.0f + smallTextHeight);
    const contentBottomWithLabels = max(contentBottom, max(120.0f + smallTextHeight, 144.0f + smallTextHeight));
    const height = 36.0f + contentBottomWithLabels + 20.0f;

    auto window = new UiWindow("RENDER MODES", rect.left, rect.top, rect.width, rect.height, [0.10f, 0.12f, 0.16f, 0.94f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 0.98f, 0.82f, 1.00f]);
    window.add(new UiButton("F  FLAT COLOR", 0.0f, 0.0f, width - 36.0f, buttonHeight, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiButton("T  LIT / TEXTURED", 0.0f, buttonHeight + 4.0f, width - 36.0f, buttonHeight, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiButton("W  WIREFRAME", 0.0f, (buttonHeight + 4.0f) * 2.0f, width - 36.0f, buttonHeight, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiButton("H  HIDDEN LINE", 0.0f, (buttonHeight + 4.0f) * 3.0f, width - 36.0f, buttonHeight, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiLabel("+ / -  SWITCH SHAPE", 0.0f, 120.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiLabel("ARROWS  ROTATE CAMERA", 0.0f, 144.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiLabel("ESC  CLOSE APPLICATION", 0.0f, 168.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f]));
    return window;
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

    auto window = new UiWindow("FONT SIZES", rect.left, rect.top, rect.width, rect.height, [0.10f, 0.12f, 0.16f, 0.94f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 0.98f, 0.82f, 1.00f]);
    window.add(new UiLabel("12 PX  THE QUICK BROWN FOX", 0.0f, 0.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiLabel("18 PX  THE QUICK BROWN FOX", 0.0f, smallFont.lineHeight + 14.0f, UiTextStyle.medium, [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiLabel("24 PX  THE QUICK BROWN FOX", 0.0f, smallFont.lineHeight + mediumFont.lineHeight + 32.0f, UiTextStyle.large, [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiLabel("REAL FONTS KEEP SIZES DISTINCT.", 0.0f, smallFont.lineHeight + mediumFont.lineHeight + largeFont.lineHeight + 52.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f]));
    return window;
}

private UiWindow buildInputWindow(HudWindowRect rect, ref const(FontAtlas) smallFont)
{
    auto window = new UiWindow("INPUT", rect.left, rect.top, rect.width, rect.height, [0.10f, 0.12f, 0.16f, 0.92f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 0.98f, 0.82f, 1.00f]);
    window.add(new UiLabel("LEFT BUTTON DRAGS THE CENTER WINDOW.", 0.0f, 0.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiLabel("CLICK OUTSIDE THE UI TO ROTATE 3D.", 0.0f, smallFont.lineHeight + 12.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiLabel("HEADER BAR IS THE DRAG HANDLE.", 0.0f, smallFont.lineHeight * 2.0f + 24.0f, UiTextStyle.small, [0.90f, 0.95f, 1.00f, 1.00f]));
    return window;
}

private UiWindow buildCenterWindow(HudWindowRect rect, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont)
{
    auto window = new UiWindow("DRAG ME", rect.left, rect.top, rect.width, rect.height, [0.10f, 0.12f, 0.16f, 0.92f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 0.98f, 0.82f, 1.00f]);
    window.add(new UiLabel("GRAB THE BLUE BAR TO MOVE THIS WINDOW.", 0.0f, 0.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiLabel("UI HITS DO NOT FALL THROUGH TO 3D.", 0.0f, smallFont.lineHeight + 12.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiLabel("OUTSIDE HITS GO TO THE OBJECT LAYER.", 0.0f, smallFont.lineHeight * 2.0f + 24.0f, UiTextStyle.small, [0.90f, 0.95f, 1.00f, 1.00f]));
    window.add(new UiLabel("DRAGGING USES THE HEADER BAR ONLY.", 0.0f, smallFont.lineHeight * 3.0f + 36.0f, UiTextStyle.small, [0.90f, 0.95f, 1.00f, 1.00f]));
    return window;
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
    float contentWidth = 0.0f;
    foreach (label; buttonLabels)
        contentWidth = max(contentWidth, textBlockWidth(smallFont, label));
    foreach (label; actionLabels)
        contentWidth = max(contentWidth, textBlockWidth(smallFont, label));

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
    const width = max(titleWidth + 24.0f, contentWidth + 36.0f);
    const smallTextHeight = textBlockHeight(smallFont);
    const mediumTextHeight = textBlockHeight(mediumFont);
    const height = 36.0f + max(max(max(0.0f + smallTextHeight, smallTextHeight + 12.0f + smallTextHeight), smallTextHeight * 2.0f + 24.0f), smallTextHeight * 3.0f + 36.0f) + 20.0f;

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
    state.middleDragging = true;
    state.dragOffsetX = cursorX - rect.left;
    state.dragOffsetY = cursorY - rect.top;
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

/** Stops any active center-window drag. */
void hudEndDrag(ref HudLayoutState state)
{
    state.middleDragging = false;
}

private float clampFloat(float value, float minimum, float maximum)
{
    return value < minimum ? minimum : (value > maximum ? maximum : value);
}
