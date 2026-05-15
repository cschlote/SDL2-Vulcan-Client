/** Shared layout measurement context for retained UI widgets.
 *
 * Widgets use this context during explicit layout passes to look up font
 * atlases and compute font-sensitive intrinsic sizes without reaching into the
 * renderer's draw-time state.
 */
module vulkan.ui.ui_layout_context;

import std.algorithm : max;

import vulkan.font.font_legacy : FontAtlas, measureTextWidth;
import vulkan.ui.ui_context : UiTextStyle;

/** Intrinsic size returned by a widget's measurement pass. */
struct UiLayoutSize
{
    float width;
    float height;
}

/** Collects font atlases for layout-time size measurement. */
struct UiLayoutContext
{
    const(FontAtlas)*[7] fonts;

    /** Returns the font atlas for the requested text style. */
    const(FontAtlas)* atlasFor(UiTextStyle style) const
    {
        return fonts[cast(size_t)style];
    }

    /** Measures the width of a text string for the requested style. */
    float textWidth(UiTextStyle style, string text) const
    {
        const atlas = atlasFor(style);
        return atlas is null ? 0.0f : measureTextWidth(*atlas, text);
    }

    /** Measures the height of a text line for the requested style. */
    float textHeight(UiTextStyle style) const
    {
        const atlas = atlasFor(style);
        return atlas is null ? 0.0f : max(atlas.lineHeight, atlas.ascent + atlas.descent);
    }
}