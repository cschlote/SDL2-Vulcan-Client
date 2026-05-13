/** $purposeofFile
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018
 * License: CC-BY-NC-SA 4.0
 *
 * Legacy helper block below is kept only until the old HUD geometry path is fully removed.
 */
module vulkan.hud;

import std.format : format;
import std.algorithm : max;
import std.math : PI;

import vulkan.font : FontAtlas;
import vulkan.pipeline : Vertex;
import vulkan.ui : UiButton, UiContainer, UiLabel, UiRenderContext, UiTextStyle, UiWindow;

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
HudOverlayGeometry buildHudOverlayVertices(float extentWidth, float extentHeight, float fps, float yawAngle, float pitchAngle, string shapeName, string renderModeName, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont, ref const(FontAtlas) largeFont)
{
    HudOverlayGeometry geometry;

    auto root = new UiContainer();
    root.add(buildStatusWindow(extentWidth, extentHeight, fps, yawAngle, pitchAngle, shapeName, renderModeName, smallFont, mediumFont));
    root.add(buildModeWindow(extentWidth, extentHeight, smallFont));
    root.add(buildSampleWindow(extentWidth, extentHeight, smallFont, mediumFont, largeFont));

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

private UiWindow buildStatusWindow(float extentWidth, float extentHeight, float fps, float yawAngle, float pitchAngle, string shapeName, string renderModeName, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont)
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
    const contentBottom = max(
        max(max(max(max(
            smallFont.lineHeight,
            34.0f + mediumFont.lineHeight),
            68.0f + smallFont.lineHeight),
            90.0f + smallFont.lineHeight),
            114.0f + smallFont.lineHeight),
        136.0f + smallFont.lineHeight);
    const height = 36.0f + contentBottom + 18.0f;
    const left = anchoredLayoutPosition(18.0f, width, extentWidth);
    const top = anchoredLayoutPosition(18.0f, height, extentHeight);

    auto window = new UiWindow(titleText, left, top, width, height, [0.10f, 0.12f, 0.16f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 0.98f, 0.82f, 1.00f]);
    window.add(new UiLabel("NATIVE WINDOW PIXELS. REAL FONTS AT 12/18/24 PX.", 0.0f, 0.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiLabel(format("FRAME RATE: %.0f FPS", fps), 0.0f, 34.0f, UiTextStyle.medium, [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiLabel(format("CAMERA YAW: %.1f DEGREES", yawAngle * 180.0f / cast(float)PI), 0.0f, 68.0f, UiTextStyle.small, [0.40f, 1.00f, 0.70f, 1.00f]));
    window.add(new UiLabel(format("CAMERA PITCH: %.1f DEGREES", pitchAngle * 180.0f / cast(float)PI), 0.0f, 90.0f, UiTextStyle.small, [0.50f, 0.86f, 1.00f, 1.00f]));
    window.add(new UiLabel(format("ACTIVE SHAPE: %s", shapeName), 0.0f, 114.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiLabel(format("CURRENT MODE: %s", renderModeName), 0.0f, 136.0f, UiTextStyle.small, [1.00f, 0.90f, 0.45f, 1.00f]));
    return window;
}

private UiWindow buildModeWindow(float extentWidth, float extentHeight, ref const(FontAtlas) smallFont)
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
    const buttonHeight = max(smallFont.lineHeight + 10.0f, 24.0f);
    const contentBottom = max(
        max(max(max(
            0.0f + buttonHeight,
            (buttonHeight + 4.0f) + buttonHeight),
            (buttonHeight + 4.0f) * 2.0f + buttonHeight),
            (buttonHeight + 4.0f) * 3.0f + buttonHeight),
        168.0f + smallFont.lineHeight);
    const contentBottomWithLabels = max(contentBottom, max(120.0f + smallFont.lineHeight, 144.0f + smallFont.lineHeight));
    const height = 36.0f + contentBottomWithLabels + 18.0f;
    const left = anchoredLayoutPosition(18.0f, width, extentWidth);
    const top = anchoredLayoutPosition(272.0f, height, extentHeight);

    auto window = new UiWindow("RENDER MODES", left, top, width, height, [0.10f, 0.12f, 0.16f, 0.94f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 0.98f, 0.82f, 1.00f]);
    window.add(new UiButton("F  FLAT COLOR", 0.0f, 0.0f, width - 36.0f, buttonHeight, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiButton("T  LIT / TEXTURED", 0.0f, buttonHeight + 4.0f, width - 36.0f, buttonHeight, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiButton("W  WIREFRAME", 0.0f, (buttonHeight + 4.0f) * 2.0f, width - 36.0f, buttonHeight, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiButton("H  HIDDEN LINE", 0.0f, (buttonHeight + 4.0f) * 3.0f, width - 36.0f, buttonHeight, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiLabel("+ / -  SWITCH SHAPE", 0.0f, 120.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiLabel("ARROWS  ROTATE CAMERA", 0.0f, 144.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiLabel("ESC  CLOSE APPLICATION", 0.0f, 168.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f]));
    return window;
}

private UiWindow buildSampleWindow(float extentWidth, float extentHeight, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont, ref const(FontAtlas) largeFont)
{
    const sampleSmall = textBlockWidth(smallFont, "12 PX  THE QUICK BROWN FOX");
    const sampleMedium = textBlockWidth(mediumFont, "18 PX  THE QUICK BROWN FOX");
    const sampleLarge = textBlockWidth(largeFont, "24 PX  THE QUICK BROWN FOX");
    const sampleFooter = textBlockWidth(smallFont, "REAL FONTS KEEP SIZES DISTINCT.");
    const contentWidth = max(max(sampleSmall, sampleMedium), max(sampleLarge, sampleFooter));
    const width = contentWidth + 36.0f;
    const contentBottom = max(
        max(max(
            0.0f + smallFont.lineHeight,
            32.0f + mediumFont.lineHeight),
            74.0f + largeFont.lineHeight),
        124.0f + smallFont.lineHeight);
    const height = 36.0f + contentBottom + 18.0f;
    const left = sampleWindowLeft(extentWidth, width);
    const top = sampleWindowTop(extentWidth, extentHeight, height);

    auto window = new UiWindow("FONT SIZES", left, top, width, height, [0.10f, 0.12f, 0.16f, 0.94f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 0.98f, 0.82f, 1.00f]);
    window.add(new UiLabel("12 PX  THE QUICK BROWN FOX", 0.0f, 0.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiLabel("18 PX  THE QUICK BROWN FOX", 0.0f, smallFont.lineHeight + 14.0f, UiTextStyle.medium, [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiLabel("24 PX  THE QUICK BROWN FOX", 0.0f, smallFont.lineHeight + mediumFont.lineHeight + 32.0f, UiTextStyle.large, [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiLabel("REAL FONTS KEEP SIZES DISTINCT.", 0.0f, smallFont.lineHeight + mediumFont.lineHeight + largeFont.lineHeight + 52.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f]));
    return window;
}

private float anchoredLayoutPosition(float preferredPosition, float widgetSpan, float availableSpan)
{
    if (availableSpan <= widgetSpan)
        return 0.0f;

    const maximumPosition = availableSpan - widgetSpan;
    return preferredPosition < maximumPosition ? preferredPosition : maximumPosition;
}

private float sampleWindowLeft(float extentWidth, float windowWidth)
{
    return extentWidth >= 720.0f ? anchoredLayoutPosition(366.0f, windowWidth, extentWidth) : anchoredLayoutPosition(18.0f, windowWidth, extentWidth);
}

private float sampleWindowTop(float extentWidth, float extentHeight, float windowHeight)
{
    if (extentWidth >= 720.0f)
        return anchoredLayoutPosition(272.0f, windowHeight, extentHeight);

    return anchoredLayoutPosition(488.0f, windowHeight, extentHeight);
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
