/** Retained image-like widget used for compact icon placeholders.
 *
 * The current UI layer does not carry arbitrary textured image resources yet,
 * so this widget gives buttons and other composites a small, explicit icon
 * surface that can later be swapped for a textured implementation without
 * changing the surrounding layout code.
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.ui.ui_image;

import vulkan.engine.pipeline : Vertex;
import vulkan.ui.ui_context : UiRenderContext;
import vulkan.ui.ui_geometry : UiImageDrawCommand;
import vulkan.ui.ui_layout_context : UiLayoutContext, UiLayoutSize;
import vulkan.ui.ui_widget : UiWidget;
import vulkan.ui.ui_widget_helpers : appendImageQuad, appendSurfaceFrame;

enum float defaultImageSize = 12.0f;

/** Small retained image placeholder rendered as a framed square. */
final class UiImage : UiWidget
{
    /** Optional renderer-facing texture asset id. Empty keeps placeholder-only rendering. */
    string assetId;
    /** Tint color applied to the texture-backed image quad. */
    float[4] tintColor;
    /** UV rectangle inside the bound asset, ordered u0, v0, u1, v1. */
    float[4] uvRect;
    /** Interior fill color. */
    float[4] fillColor;
    /** Border color around the image surface. */
    float[4] borderColor;

    /** Creates a retained compact image surface.
     *
     * Params:
     *   width = Optional explicit width in pixels.
     *   height = Optional explicit height in pixels.
     *   fillColor = Interior fill color.
     *   borderColor = Border color around the image surface.
     */
    this(float width = defaultImageSize, float height = defaultImageSize, float[4] fillColor = [0.22f, 0.26f, 0.34f, 1.0f], float[4] borderColor = [0.64f, 0.72f, 0.88f, 1.0f])
    {
        super(0.0f, 0.0f, width, height);
        this.fillColor = fillColor;
        this.borderColor = borderColor;
        tintColor = [1.0f, 1.0f, 1.0f, 1.0f];
        uvRect = [0.0f, 0.0f, 1.0f, 1.0f];
    }

    /** Assigns the texture asset id requested during rendering. */
    void setAsset(string assetId, float[4] uvRect = [0.0f, 0.0f, 1.0f, 1.0f])
    {
        this.assetId = assetId;
        this.uvRect = uvRect;
    }

    /** Returns true when this image requests a texture-backed renderer path. */
    bool hasTextureAsset() const
    {
        return assetId.length != 0;
    }

protected:
    override UiLayoutSize measureSelf(ref UiLayoutContext context)
    {
        const measuredWidth = preferredWidth > 0.0f ? preferredWidth : defaultImageSize;
        const measuredHeight = preferredHeight > 0.0f ? preferredHeight : defaultImageSize;
        setLayoutHint(measuredWidth, measuredHeight, measuredWidth, measuredHeight, measuredWidth, measuredHeight);
        return UiLayoutSize(measuredWidth, measuredHeight);
    }

    override void renderSelf(ref UiRenderContext context)
    {
        if (hasTextureAsset())
            appendImageQuad(context, assetId, 0.0f, 0.0f, width, height, context.depthBase - 0.0005f, tintColor, fillColor, uvRect);
        appendSurfaceFrame(context, 0.0f, 0.0f, width, height, fillColor, borderColor, context.depthBase);
    }
}

@("UiImage measures its configured size")
unittest
{
    UiLayoutContext context;
    auto image = new UiImage(14.0f, 9.0f);

    const size = image.measure(context);

    assert(size.width == 14.0f);
    assert(size.height == 9.0f);
}

@("UiImage emits image draw intent while keeping placeholder fallback")
unittest
{
    UiRenderContext context;
    context.extentWidth = 100.0f;
    context.extentHeight = 100.0f;
    Vertex[] panels;
    UiImageDrawCommand[] images;
    context.panels = &panels;
    context.images = &images;

    auto image = new UiImage(16.0f, 12.0f);
    image.setAsset("demo/icon");
    image.render(context);

    assert(images.length == 1);
    assert(images[0].assetId == "demo/icon");
    assert(panels.length > 0);
}
