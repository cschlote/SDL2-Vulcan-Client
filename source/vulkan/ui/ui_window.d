/** Retained window widget with title bar and content region.
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.ui.ui_window;

import vulkan.ui.ui_context : UiRenderContext, UiTextStyle;
import vulkan.ui.ui_widget : UiWidget;
import vulkan.ui.ui_widget_helpers : appendTextLine, appendWindowFrame;

/** Simple retained window with a title bar and a content region. */
final class UiWindow : UiWidget
{
    string title;
    float[4] bodyColor;
    float[4] headerColor;
    float[4] titleColor;
    float headerHeight = 7.0f;

    this(string title, float x, float y, float width, float height, float[4] bodyColor, float[4] headerColor, float[4] titleColor)
    {
        super(x, y, width, height);
        this.title = title;
        this.bodyColor = bodyColor;
        this.headerColor = headerColor;
        this.titleColor = titleColor;
        childOffsetX = 18.0f;
        childOffsetY = 36.0f;
    }

protected:
    override void renderSelf(ref UiRenderContext context)
    {
        appendWindowFrame(context, 0.0f, 0.0f, width, height, headerHeight, bodyColor, headerColor, context.depthBase);
        appendTextLine(context, UiTextStyle.medium, title, 12.0f, 6.0f, titleColor, context.depthBase - 0.001f);
    }
}
