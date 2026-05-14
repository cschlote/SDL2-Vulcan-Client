/** Simple retained button widget. */
module vulkan.ui.ui_button;

import vulkan.ui.ui_context : UiRenderContext, UiTextStyle;
import vulkan.ui.ui_widget : UiWidget;
import vulkan.ui.ui_widget_helpers : appendButtonFrame, appendTextLine;

/** Simple gadget-style button used for future interactive UI work. */
final class UiButton : UiWidget
{
    string caption;
    float[4] bodyColor;
    float[4] borderColor;
    float[4] textColor;
    UiTextStyle style;

    this(string caption, float x, float y, float width, float height, float[4] bodyColor, float[4] borderColor, float[4] textColor, UiTextStyle style = UiTextStyle.small)
    {
        super(x, y, width, height);
        this.caption = caption;
        this.bodyColor = bodyColor;
        this.borderColor = borderColor;
        this.textColor = textColor;
        this.style = style;
    }

protected:
    override void renderSelf(ref UiRenderContext context)
    {
        appendButtonFrame(context, 0.0f, 0.0f, width, height, bodyColor, borderColor, context.depthBase);
        appendTextLine(context, style, caption, 10.0f, 5.0f, textColor, context.depthBase - 0.001f);
    }
}
