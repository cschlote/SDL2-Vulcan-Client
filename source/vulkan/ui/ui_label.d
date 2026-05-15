/** Simple retained text label widget.
 *
 * This module defines a simple text label widget that can be used for future interactive
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.ui.ui_label;

import vulkan.font.font_legacy : appendText;
import vulkan.ui.ui_context : UiRenderContext, UiTextStyle;
import vulkan.ui.ui_widget : UiWidget;
import vulkan.ui.ui_widget_helpers : appendTextLine;

/** Simple text widget. */
final class UiLabel : UiWidget
{
    string text;
    UiTextStyle style;
    float[4] color;

    this(const(string) text, float x, float y, UiTextStyle style, float[4] color, float height = 0.0f)
    {
        this(text, x, y, style, color, 0.0f, height);
    }

    this(const(string) text, float x, float y, UiTextStyle style, float[4] color, float width, float height)
    {
        super(x, y, width, height);
        this.text = cast(string)text;
        this.style = style;
        this.color = color;
    }

protected:
    override void renderSelf(ref UiRenderContext context)
    {
        appendTextLine(context, style, text, 0.0f, 0.0f, color, context.depthBase - 0.001f);
    }
}

/** Multiline text block widget. */
final class UiTextBlock : UiWidget
{
    string text;
    UiTextStyle style;
    float[4] color;

    this(const(string) text, float x, float y, UiTextStyle style, float[4] color, float height = 0.0f)
    {
        this(text, x, y, style, color, 0.0f, height);
    }

    this(const(string) text, float x, float y, UiTextStyle style, float[4] color, float width, float height)
    {
        super(x, y, width, height);
        this.text = cast(string)text;
        this.style = style;
        this.color = color;
    }

protected:
    override void renderSelf(ref UiRenderContext context)
    {
        const atlas = context.atlasFor(style);
        auto vertices = context.textVerticesFor(style);

        if (atlas is null || vertices is null)
            return;

        appendText(*vertices, *atlas, text, context.originX, context.originY, context.depthBase - 0.001f, color, context.extentWidth, context.extentHeight);
    }
}
