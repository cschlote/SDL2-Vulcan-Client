/** Simple retained button widget.
 *
 * This module defines a simple button widget that can be used for future interactive
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.ui.ui_button;

import vulkan.ui.ui_event : UiPointerEvent, UiPointerEventKind;
import vulkan.ui.ui_context : UiRenderContext, UiTextStyle;
import vulkan.ui.ui_layout_context : UiLayoutContext, UiLayoutSize;
import vulkan.ui.ui_widget : UiWidget;
import vulkan.ui.ui_widget_helpers : appendButtonFrame, appendTextLine;
import logging : logLine;

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

    /**
     * Creates a retained button with a fixed caption and optional text offset.
     *
     * The text offsets are useful for compact chrome buttons such as a close
     * box, where the default body-text padding would sit too far inside the
     * small frame.
     */
    this(string caption, float x, float y, float width, float height, float[4] bodyColor, float[4] borderColor, float[4] textColor, UiTextStyle style = UiTextStyle.medium, float textOffsetX = 10.0f, float textOffsetY = 5.0f)
    {
        super(x, y, width, height);
        this.caption = caption;
        this.bodyColor = bodyColor;
        this.borderColor = borderColor;
        this.textColor = textColor;
        this.style = style;
        this.textOffsetX = textOffsetX;
        this.textOffsetY = textOffsetY;
    }

protected:
    override UiLayoutSize measureSelf(ref UiLayoutContext context)
    {
        const textWidth = context.textWidth(style, caption);
        const textHeight = context.textHeight(style);
        const measuredWidth = width > 0.0f ? width : textWidth + textOffsetX * 2.0f;
        const measuredHeight = height > 0.0f ? height : textHeight + textOffsetY * 2.0f;
        setLayoutHint(measuredWidth, measuredHeight, measuredWidth, measuredHeight, measuredWidth, measuredHeight, 0.0f, 0.0f);
        return UiLayoutSize(measuredWidth, measuredHeight);
    }

    override void renderSelf(ref UiRenderContext context)
    {
        appendButtonFrame(context, 0.0f, 0.0f, width, height, bodyColor, borderColor, context.depthBase);
        appendTextLine(context, style, caption, textOffsetX, textOffsetY, textColor, context.depthBase - 0.001f);
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
