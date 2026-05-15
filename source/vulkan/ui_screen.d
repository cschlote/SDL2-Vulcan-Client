
/** Screen-level coordinator for the retained HUD layer.
 *
 * The renderer keeps the screen-wide UI state in one place through this type
 * so layout, overlay generation, and the settings draft all share the same
 * ownership boundary.
 *
 * See_Also:
 *   source/vulkan/ui_layer.d
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.ui_screen;

import demo_settings : DemoSettings;
import vulkan.font.font_legacy : FontAtlas;
import vulkan.ui_layer : HudLayout, HudLayoutState, HudOverlayGeometry, buildHudLayout, buildHudOverlayVertices;

/** Owns the screen-wide state used by the demo HUD. */
struct UiScreen
{
    /** Persistent window geometry and visibility flags for the HUD. */
    HudLayoutState layoutState;
    /** Mutable draft that the settings dialog edits before Apply. */
    DemoSettings settingsDraft;
    /** Tracks whether the scene is currently dragged outside the HUD. */
    bool sceneMouseDragging;

    /** Initializes the screen state from the live demo settings bundle.
     *
     * Params:
     *   liveSettings = Persistent settings bundle, or null when none exists.
     * Returns:
     *   Nothing.
     */
    void initialize(const(DemoSettings)* liveSettings)
    {
        settingsDraft = liveSettings !is null ? *liveSettings : DemoSettings.init;
        layoutState = HudLayoutState.init;
        sceneMouseDragging = false;
    }

    /** Builds the current HUD layout from the screen-owned state.
     *
     * Params:
     *   extentWidth = Swapchain width in pixels.
     *   extentHeight = Swapchain height in pixels.
     *   fps = Last measured frame rate.
     *   yawAngle = Current yaw angle in radians.
     *   pitchAngle = Current pitch angle in radians.
     *   shapeName = Name of the active polyhedron.
     *   renderModeName = Name of the active render mode.
     *   buildVersion = Git describe string for the build.
     *   platformName = SDL platform string.
     *   vulkanApiVersion = Vulkan API version used by the renderer.
     *   fontAtlases = Font atlases indexed by UiTextStyle.
     *   smallFont = Font atlas used for compact body copy.
     *   mediumFont = Font atlas used for labels and titles.
     *   largeFont = Font atlas used for comparison samples.
     * Returns:
     *   The current HUD layout in pixel coordinates.
     */
    HudLayout buildLayout(float extentWidth, float extentHeight, float fps, float yawAngle, float pitchAngle, string shapeName, string renderModeName, string buildVersion, string platformName, uint vulkanApiVersion, const(FontAtlas)[] fontAtlases, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont, ref const(FontAtlas) largeFont)
    {
        return buildHudLayout(extentWidth, extentHeight, fps, yawAngle, pitchAngle, shapeName, renderModeName, buildVersion, platformName, vulkanApiVersion, layoutState, fontAtlases, smallFont, mediumFont, largeFont);
    }

    /** Builds the HUD overlay geometry from the current screen state.
     *
     * Params:
     *   extentWidth = Swapchain width in pixels.
     *   extentHeight = Swapchain height in pixels.
     *   fps = Last measured frame rate.
     *   yawAngle = Current yaw angle in radians.
     *   pitchAngle = Current pitch angle in radians.
     *   shapeName = Name of the active polyhedron.
     *   renderModeName = Name of the active render mode.
     *   buildVersion = Git describe string for the build.
     *   platformName = SDL platform string.
     *   vulkanApiVersion = Vulkan API version used by the renderer.
     *   onFlatColor = Callback for the flat-color mode button.
     *   onLitTextured = Callback for the lit/textured mode button.
     *   onWireframe = Callback for the wireframe mode button.
     *   onHiddenLine = Callback for the hidden-line mode button.
     *   onPreviousShape = Callback for the previous-shape button.
     *   onNextShape = Callback for the next-shape button.
     *   onOpenSettings = Callback for the settings button.
     *   onApplySettings = Callback for the settings dialog Apply button.
     *   fontAtlases = Font atlases indexed by UiTextStyle.
     *   smallFont = Font atlas used for compact body copy.
     *   mediumFont = Font atlas used for labels and titles.
     *   largeFont = Font atlas used for comparison samples.
     * Returns:
     *   The current overlay geometry ready for upload.
     */
    HudOverlayGeometry buildOverlayVertices(float extentWidth, float extentHeight, float fps, float yawAngle, float pitchAngle, string shapeName, string renderModeName, string buildVersion, string platformName, uint vulkanApiVersion, void delegate() onFlatColor, void delegate() onLitTextured, void delegate() onWireframe, void delegate() onHiddenLine, void delegate() onPreviousShape, void delegate() onNextShape, void delegate() onOpenSettings, void delegate() onApplySettings, const(FontAtlas)[] fontAtlases, ref const(FontAtlas) smallFont, ref const(FontAtlas) mediumFont, ref const(FontAtlas) largeFont)
    {
        return buildHudOverlayVertices(extentWidth, extentHeight, fps, yawAngle, pitchAngle, shapeName, renderModeName, buildVersion, layoutState, settingsDraft, platformName, vulkanApiVersion, onFlatColor, onLitTextured, onWireframe, onHiddenLine, onPreviousShape, onNextShape, onOpenSettings, onApplySettings, fontAtlases, smallFont, mediumFont, largeFont);
    }

    /** Opens the settings dialog with a fresh draft copy of the live bundle.
     *
     * Params:
     *   liveSettings = Persistent settings bundle, or null when none exists.
     * Returns:
     *   Nothing.
     */
    void openSettingsDialog(const(DemoSettings)* liveSettings)
    {
        if (liveSettings !is null)
            settingsDraft = *liveSettings;

        layoutState.settingsVisible = true;
    }

    /** Toggles the settings dialog and refreshes the draft on open.
     *
     * Params:
     *   liveSettings = Persistent settings bundle, or null when none exists.
     * Returns:
     *   Nothing.
     */
    void toggleSettingsDialog(const(DemoSettings)* liveSettings)
    {
        if (layoutState.settingsVisible)
        {
            layoutState.settingsVisible = false;
            return;
        }

        openSettingsDialog(liveSettings);
    }
}

@("UiScreen refreshes the draft when opening the settings dialog")
unittest
{
    UiScreen screen;
    DemoSettings liveSettings;

    liveSettings.gameplay.startupShape = "ICOSAHEDRON";
    screen.initialize(&liveSettings);

    assert(screen.settingsDraft.gameplay.startupShape == "ICOSAHEDRON");

    liveSettings.gameplay.startupShape = "TETRAHEDRON";
    screen.toggleSettingsDialog(&liveSettings);

    assert(screen.layoutState.settingsVisible);
    assert(screen.settingsDraft.gameplay.startupShape == "TETRAHEDRON");

    screen.toggleSettingsDialog(&liveSettings);

    assert(!screen.layoutState.settingsVisible);
}