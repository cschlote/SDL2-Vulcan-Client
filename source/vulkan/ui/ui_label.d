/** Simple retained text label widget.
 *
 * This module defines a simple text label widget that can be used for future interactive
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.ui.ui_label;

import vulkan.ui.ui_context : UiRenderContext, UiTextStyle;
import vulkan.ui.ui_widget : UiWidget;
import vulkan.ui.ui_widget_helpers : appendTextLine;

/** Simple text widget. */
final class UiLabel : UiWidget
{
    string text;
    UiTextStyle style;
    float[4] color;

    this(string text, float x, float y, UiTextStyle style, float[4] color)
    {
        super(x, y, 0, 0);
        this.text = text;
        this.style = style;
        this.color = color;
    }

protected:
    override void renderSelf(ref UiRenderContext context)
    {
        appendTextLine(context, style, text, 0.0f, 0.0f, color, context.depthBase - 0.001f);
    }
}
