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
    root.add(buildStatusWindow(extentWidth, extentHeight, fps, yawAngle, pitchAngle, shapeName, renderModeName));
    root.add(buildModeWindow(extentWidth, extentHeight));
    root.add(buildSampleWindow(extentWidth, extentHeight));

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

private UiWindow buildStatusWindow(float extentWidth, float extentHeight, float fps, float yawAngle, float pitchAngle, string shapeName, string renderModeName)
{
    const left = anchoredLayoutPosition(18.0f, 612.0f, extentWidth);
    const top = anchoredLayoutPosition(18.0f, 236.0f, extentHeight);
    const width = 612.0f;
    const height = 236.0f;

    auto window = new UiWindow("DESKTOP OVERLAY", left, top, width, height, [0.10f, 0.12f, 0.16f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 0.98f, 0.82f, 1.00f]);
    window.add(new UiLabel("NATIVE WINDOW PIXELS. REAL FONTS AT 12/18/24 PX.", 0.0f, 0.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiLabel(format("FRAME RATE: %.0f FPS", fps), 0.0f, 34.0f, UiTextStyle.medium, [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiLabel(format("CAMERA YAW: %.1f DEGREES", yawAngle * 180.0f / cast(float)PI), 0.0f, 68.0f, UiTextStyle.small, [0.40f, 1.00f, 0.70f, 1.00f]));
    window.add(new UiLabel(format("CAMERA PITCH: %.1f DEGREES", pitchAngle * 180.0f / cast(float)PI), 0.0f, 90.0f, UiTextStyle.small, [0.50f, 0.86f, 1.00f, 1.00f]));
    window.add(new UiLabel(format("ACTIVE SHAPE: %s", shapeName), 0.0f, 114.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiLabel(format("CURRENT MODE: %s", renderModeName), 0.0f, 136.0f, UiTextStyle.small, [1.00f, 0.90f, 0.45f, 1.00f]));
    return window;
}

private UiWindow buildModeWindow(float extentWidth, float extentHeight)
{
    const left = anchoredLayoutPosition(18.0f, 334.0f, extentWidth);
    const top = anchoredLayoutPosition(272.0f, 198.0f, extentHeight);
    const width = 334.0f;
    const height = 198.0f;

    auto window = new UiWindow("RENDER MODES", left, top, width, height, [0.10f, 0.12f, 0.16f, 0.94f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 0.98f, 0.82f, 1.00f]);
    window.add(new UiButton("F  FLAT COLOR", 0.0f, 0.0f, 276.0f, 24.0f, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiButton("T  LIT / TEXTURED", 0.0f, 28.0f, 276.0f, 24.0f, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiButton("W  WIREFRAME", 0.0f, 56.0f, 276.0f, 24.0f, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiButton("H  HIDDEN LINE", 0.0f, 84.0f, 276.0f, 24.0f, [0.16f, 0.18f, 0.24f, 0.96f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiLabel("+ / -  SWITCH SHAPE", 0.0f, 120.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiLabel("ARROWS  ROTATE CAMERA", 0.0f, 144.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiLabel("ESC  CLOSE APPLICATION", 0.0f, 168.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f]));
    return window;
}

private UiWindow buildSampleWindow(float extentWidth, float extentHeight)
{
    const left = sampleWindowLeft(extentWidth);
    const top = sampleWindowTop(extentWidth, extentHeight);
    const width = 266.0f;
    const height = 198.0f;

    auto window = new UiWindow("FONT SIZES", left, top, width, height, [0.10f, 0.12f, 0.16f, 0.94f], [0.20f, 0.56f, 0.98f, 1.00f], [1.00f, 0.98f, 0.82f, 1.00f]);
    window.add(new UiLabel("12 PX  THE QUICK BROWN FOX", 0.0f, 0.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiLabel("18 PX  THE QUICK BROWN FOX", 0.0f, 32.0f, UiTextStyle.medium, [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiLabel("24 PX  THE QUICK BROWN FOX", 0.0f, 74.0f, UiTextStyle.large, [1.00f, 1.00f, 1.00f, 1.00f]));
    window.add(new UiLabel("REAL FONTS KEEP SIZES DISTINCT.", 0.0f, 124.0f, UiTextStyle.small, [1.00f, 1.00f, 1.00f, 1.00f]));
    return window;
}

private float anchoredLayoutPosition(float preferredPosition, float widgetSpan, float availableSpan)
{
    if (availableSpan <= widgetSpan)
        return 0.0f;

    const maximumPosition = availableSpan - widgetSpan;
    return preferredPosition < maximumPosition ? preferredPosition : maximumPosition;
}

private float sampleWindowLeft(float extentWidth)
{
    return extentWidth >= 720.0f ? 366.0f : 18.0f;
}

private float sampleWindowTop(float extentWidth, float extentHeight)
{
    if (extentWidth >= 720.0f)
        return anchoredLayoutPosition(272.0f, 198.0f, extentHeight);

    return anchoredLayoutPosition(488.0f, 198.0f, extentHeight);
}
