/** Shared rendering context and text-style selection for retained UI widgets.
 *
 * This module holds the data that every widget needs to place quads and text
 * into the shared overlay buffers.
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.ui.ui_context;

import vulkan.font.font_legacy : FontAtlas;
import vulkan.engine.pipeline : Vertex;

/** Selects the font size used by a widget. */
enum UiTextStyle
{
    /** 7 px sample text. */
    sample7,
    /** Small body text. */
    sample8,
    /** 9 px sample text. */
    sample9,
    /** Medium labels and titles. */
    sample10,
    /** 11 px sample text. */
    sample11,
    /** Large comparison text. */
    sample12,
    /** 8 px monospace sample text. */
    sampleMono,

    small = sample9, // alias for legacy style name
    medium = sample10, // alias for legacy style name
    large = sample12 // alias for legacy style name
}

/** Collects the geometry targets and font atlases for a UI frame.
 *
 * Widgets render into the shared overlay buffers through this context. The
 * renderer feeds it with indexed atlases and the per-frame vertex lists.
 */
struct UiRenderContext
{
    /** Target viewport width in pixels. */
    float extentWidth;
    /** Target viewport height in pixels. */
    float extentHeight;
    /** Current X offset relative to the parent widget. */
    float originX;
    /** Current Y offset relative to the parent widget. */
    float originY;
    /** Base Z depth used to keep widget layers stable. */
    float depthBase;
    /** Draws widget bounds as a debug overlay when enabled. */
    bool debugWidgetBounds;
    /** Font atlases indexed by UiTextStyle. */
    const(FontAtlas)*[7] fonts;
    /** Destination vertex list for window and panel quads. */
    Vertex[]* panels;
    /** Destination vertex lists indexed by UiTextStyle. */
    Vertex[]*[7] textLayers;

    /** Creates a child context relative to the current origin. */
    UiRenderContext offset(float deltaX, float deltaY)
    {
        auto next = this;
        next.originX += deltaX;
        next.originY += deltaY;
        return next;
    }

    /** Returns the font atlas for the requested text style. */
    const(FontAtlas)* atlasFor(UiTextStyle style) const
    {
        return fonts[cast(size_t)style];
    }

    /** Returns the active vertex buffer for the requested text style. */
    Vertex[]* textVerticesFor(UiTextStyle style) const
    {
        return cast(Vertex[]*)textLayers[cast(size_t)style];
    }
}
