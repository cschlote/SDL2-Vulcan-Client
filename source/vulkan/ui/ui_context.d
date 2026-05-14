/** Shared rendering context and text-style selection for retained UI widgets.
 *
 * This module holds the data that every widget needs to place quads and text
 * into the shared overlay buffers.
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.ui.ui_context;

import vulkan.font : FontAtlas;
import vulkan.pipeline : Vertex;

/** Selects the font size used by a widget. */
enum UiTextStyle
{
    /** Small body text. */
    small,
    /** Medium labels and titles. */
    medium,
    /** Large comparison text. */
    large,
}

/** Collects the geometry targets and font atlases for a UI frame.
 *
 * Widgets render into the shared overlay buffers through this context. The
 * renderer feeds it with the three atlas sizes and the per-frame vertex lists.
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
    /** Font atlas for small text. */
    const(FontAtlas)* smallFont;
    /** Font atlas for medium text. */
    const(FontAtlas)* mediumFont;
    /** Font atlas for large text. */
    const(FontAtlas)* largeFont;
    /** Destination vertex list for window and panel quads. */
    Vertex[]* panels;
    /** Destination vertex list for small text quads. */
    Vertex[]* smallText;
    /** Destination vertex list for medium text quads. */
    Vertex[]* mediumText;
    /** Destination vertex list for large text quads. */
    Vertex[]* largeText;

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
        final switch (style)
        {
            case UiTextStyle.small: return smallFont;
            case UiTextStyle.medium: return mediumFont;
            case UiTextStyle.large: return largeFont;
        }
    }
}