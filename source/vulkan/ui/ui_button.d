/** Simple retained button widget.
 *
 * This module defines a retained button widget with an explicit frame and an
 * inner horizontal content row.
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.ui.ui_button;

import logging : logLine;
import vulkan.ui.ui_context : UiRenderContext, UiTextStyle;
import vulkan.ui.ui_event : UiPointerEvent, UiPointerEventKind;
import vulkan.ui.ui_layout_context : UiLayoutContext, UiLayoutSize;
import vulkan.ui.ui_widget : UiWidget;
import vulkan.ui.ui_image : UiImage;
import vulkan.ui.ui_label : UiLabel;
import vulkan.ui.ui_layout : UiHBox, UiSpacer;
import vulkan.ui.ui_widget_helpers : appendSurfaceFrame;

enum float buttonInnerMarginX = 10.0f;
enum float buttonInnerMarginY = 5.0f;
enum float buttonContentSpacing = 6.0f;

/** Simple gadget-style button used for future interactive UI work. */
final class UiButton : UiWidget
{
    string caption;
    float[4] bodyColor;
    float[4] borderColor;
    float[4] textColor;
    UiTextStyle style;
    float textOffsetX;
    float textOffsetY;
    void delegate() onClick;

    private UiHBox contentRow;
    private UiSpacer leadingSpacer;
    private UiSpacer trailingSpacer;
    private UiSpacer imageSpacer;
    private UiLabel captionLabel;
    private UiImage image;

    /**
     * Creates a retained button with a label-only inner layout.
     *
     * Params:
     *   caption = Button text shown inside the inner label.
     *   x = Left edge in parent coordinates.
     *   y = Top edge in parent coordinates.
     *   width = Optional explicit width in pixels.
     *   height = Optional explicit height in pixels.
     *   bodyColor = Button fill color.
     *   borderColor = Button border color.
     *   textColor = Label text color.
     *   style = Font style used for the label.
     *   textOffsetX = Inner horizontal margin around the content row.
     *   textOffsetY = Inner vertical margin around the content row.
     *
     * Returns:
     *   A retained button with a framed body and a label inside.
     */
    this(string caption, float x, float y, float width, float height, float[4] bodyColor, float[4] borderColor, float[4] textColor, UiTextStyle style = UiTextStyle.medium, float textOffsetX = buttonInnerMarginX, float textOffsetY = buttonInnerMarginY)
    {
        this(cast(UiImage)null, caption, x, y, width, height, bodyColor, borderColor, textColor, style, textOffsetX, textOffsetY);
    }

    /**
     * Creates a retained button with an optional icon and a label.
     *
     * Params:
     *   image = Optional icon widget placed before the label.
     *   caption = Button text shown inside the inner label.
     *   x = Left edge in parent coordinates.
     *   y = Top edge in parent coordinates.
     *   width = Optional explicit width in pixels.
     *   height = Optional explicit height in pixels.
     *   bodyColor = Button fill color.
     *   borderColor = Button border color.
     *   textColor = Label text color.
     *   style = Font style used for the label.
     *   textOffsetX = Inner horizontal margin around the content row.
     *   textOffsetY = Inner vertical margin around the content row.
     *
     * Returns:
     *   A retained button with a framed body and a composite inner row.
     */
    this(UiImage image, string caption, float x, float y, float width, float height, float[4] bodyColor, float[4] borderColor, float[4] textColor, UiTextStyle style = UiTextStyle.medium, float textOffsetX = buttonInnerMarginX, float textOffsetY = buttonInnerMarginY)
    {
        super(x, y, width, height);
        this.caption = caption;
        this.bodyColor = bodyColor;
        this.borderColor = borderColor;
        this.textColor = textColor;
        this.style = style;
        this.textOffsetX = textOffsetX;
        this.textOffsetY = textOffsetY;

        contentRow = new UiHBox(0.0f, 0.0f, 0.0f, 0.0f, 0.0f, textOffsetX, textOffsetY, textOffsetX, textOffsetY);

        leadingSpacer = new UiSpacer();
        leadingSpacer.setLayoutHint(0.0f, 0.0f, 0.0f, 0.0f, float.max, 0.0f, 1.0f, 0.0f);
        contentRow.add(leadingSpacer);

        this.image = image;
        if (image !is null)
        {
            contentRow.add(image);
            imageSpacer = new UiSpacer(buttonContentSpacing, 0.0f);
            contentRow.add(imageSpacer);
        }

        captionLabel = new UiLabel(caption, 0.0f, 0.0f, style, textColor);
        contentRow.add(captionLabel);

        trailingSpacer = new UiSpacer();
        trailingSpacer.setLayoutHint(0.0f, 0.0f, 0.0f, 0.0f, float.max, 0.0f, 1.0f, 0.0f);
        contentRow.add(trailingSpacer);
        super.add(contentRow);
    }

protected:
    override UiLayoutSize measureSelf(ref UiLayoutContext context)
    {
        const contentSize = contentRow.measure(context);
        const measuredWidth = preferredWidth > 0.0f ? preferredWidth : contentSize.width;
        const measuredHeight = preferredHeight > 0.0f ? preferredHeight : contentSize.height;
        setLayoutHint(measuredWidth, measuredHeight, measuredWidth, measuredHeight, measuredWidth, measuredHeight);
        return UiLayoutSize(measuredWidth, measuredHeight);
    }

    override void layoutSelf(ref UiLayoutContext context)
    {
        const captionHeight = captionLabel.measure(context).height;
        const imageHeight = image is null ? 0.0f : image.measure(context).height;
        const contentHeight = imageHeight > captionHeight ? imageHeight : captionHeight;
        const centeredMarginY = height > contentHeight ? (height - contentHeight) * 0.5f : textOffsetY;

        contentRow.paddingTop = centeredMarginY;
        contentRow.paddingBottom = centeredMarginY;
        contentRow.x = 0.0f;
        contentRow.y = 0.0f;
        contentRow.width = width;
        contentRow.height = height;
        contentRow.layout(context);
    }

    override void renderSelf(ref UiRenderContext context)
    {
        appendSurfaceFrame(context, 0.0f, 0.0f, width, height, bodyColor, borderColor, context.depthBase);
    }

    override bool handlePointerEvent(ref UiPointerEvent event)
    {
        if (event.kind != UiPointerEventKind.buttonDown || event.button != 1)
            return false;

        logLine("UiButton click: ", caption);
        if (onClick !is null)
            onClick();

        return true;
    }
}

@("UiButton creates a label-only content row")
unittest
{
    auto button = new UiButton("PLAY", 0.0f, 0.0f, 0.0f, 0.0f, [0.0f, 0.0f, 0.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f]);

    assert(button.children.length == 1);
    auto row = cast(UiHBox)button.children[0];
    assert(row !is null);
    assert(row.children.length == 3);
    assert(cast(UiSpacer)row.children[0] !is null);
    assert(cast(UiLabel)row.children[1] !is null);
    assert(cast(UiSpacer)row.children[2] !is null);
}

@("UiButton can host an image and a label")
unittest
{
    auto icon = new UiImage(8.0f, 8.0f);
    auto button = new UiButton(icon, "PLAY", 0.0f, 0.0f, 0.0f, 0.0f, [0.0f, 0.0f, 0.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f]);

    assert(button.children.length == 1);
    auto row = cast(UiHBox)button.children[0];
    assert(row !is null);
    assert(row.children.length == 5);
    assert(cast(UiSpacer)row.children[0] !is null);
    assert(cast(UiImage)row.children[1] !is null);
    assert(cast(UiSpacer)row.children[2] !is null);
    assert(cast(UiLabel)row.children[3] !is null);
    assert(cast(UiSpacer)row.children[4] !is null);
}
