/** Renderer-facing geometry ranges produced by retained UI traversal.
 *
 * The UI renderer uploads panel and text vertices into separate buffers. These
 * data types keep the generated geometry grouped by logical window so the
 * renderer can preserve retained window stacking without knowing widget
 * internals.
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.ui.ui_geometry;

import vulkan.engine.pipeline : Vertex;

/** Describes one contiguous draw block inside the overlay buffers.
 *
 * Each range maps one logical window to a contiguous set of panel and text
 * vertices so the renderer can preserve the intended stacking order.
 */
struct UiWindowDrawRange
{
    /** Start index for panel vertices. */
    uint panelsStart;
    /** Vertex count for panel geometry. */
    uint panelsCount;
    /** Start index for image/icon draw intents. */
    uint imagesStart;
    /** Image/icon intent count. */
    uint imagesCount;
    /** Start indices for text vertices, indexed by UiTextStyle. */
    uint[7] textStarts;
    /** Vertex counts for text geometry, indexed by UiTextStyle. */
    uint[7] textCounts;
    /** Presentation alpha for future window transition rendering. */
    float alpha = 1.0f;
    /** Presentation scale for future window transition rendering. */
    float scale = 1.0f;
    /** Presentation X offset in pixels for future window transition rendering. */
    float offsetX;
    /** Presentation Y offset in pixels for future window transition rendering. */
    float offsetY;
}

/** Describes one texture-backed UI image quad requested by a retained widget.
 *
 * The renderer resolves `assetId` through its UI image asset registry, rewrites
 * the quad UVs to the registered atlas region, and draws `vertices` through the
 * dedicated image overlay layer. The widget may still emit a framed placeholder
 * panel as fallback styling.
 */
struct UiImageDrawCommand
{
    /** Application or renderer-owned texture asset id. */
    string assetId;
    /** Six vertices that form one textured quad. */
    Vertex[6] vertices;
    /** Fallback fill color used by the placeholder widget path. */
    float[4] fallbackColor;
}

/** Holds the panel and text geometry for the UI overlay.
 *
 * The renderer uploads each vertex list independently and uses the draw ranges
 * to emit one logical window at a time.
 */
struct UiOverlayGeometry
{
    /** Window body and header quads. */
    Vertex[] panels;
    /** Texture-backed image/icon draw intents. */
    UiImageDrawCommand[] images;
    /** Text quads indexed by UiTextStyle. */
    Vertex[][7] textLayers;
    /** Draw ranges that keep each window's render calls contiguous. */
    UiWindowDrawRange[] windows;
}
