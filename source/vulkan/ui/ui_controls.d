/** Basic retained input controls for demo and engine UI.
 *
 * These widgets provide small, font-sensitive controls that can be composed
 * inside the existing box layouts without application-specific behavior.
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.ui.ui_controls;

import std.algorithm : max;
import std.format : format;

import vulkan.ui.ui_context : UiRenderContext, UiTextStyle;
import vulkan.ui.ui_event : UiPointerEvent, UiPointerEventKind;
import vulkan.ui.ui_layout_context : UiLayoutContext, UiLayoutSize;
import vulkan.ui.ui_widget : UiWidget;
import vulkan.ui.ui_widget_helpers : appendSurfaceFrame, appendTextLine, appendQuad;

private enum float controlHeight = 28.0f;
private enum float controlPaddingX = 10.0f;
private enum float controlGap = 8.0f;
private enum float fallbackGlyphWidth = 8.0f;
private enum float fallbackTextHeight = 14.0f;

private immutable float[4] defaultFillColor = [0.16f, 0.18f, 0.24f, 0.96f];
private immutable float[4] defaultBorderColor = [0.20f, 0.56f, 0.98f, 1.00f];
private immutable float[4] defaultAccentColor = [0.34f, 0.82f, 0.46f, 1.00f];
private immutable float[4] defaultTextColor = [1.00f, 1.00f, 1.00f, 1.00f];
private immutable float[4] defaultMutedColor = [0.50f, 0.54f, 0.62f, 1.00f];

private float clampFloat(float value, float minimum, float maximum)
{
    return value < minimum ? minimum : (value > maximum ? maximum : value);
}

private float textWidth(ref UiLayoutContext context, UiTextStyle style, string text)
{
    const measured = context.textWidth(style, text);
    return measured > 0.0f ? measured : cast(float)text.length * fallbackGlyphWidth;
}

private float textHeight(ref UiLayoutContext context, UiTextStyle style)
{
    const measured = context.textHeight(style);
    return measured > 0.0f ? measured : fallbackTextHeight;
}

private float centeredTextY(float height, float textHeight)
{
    return height > textHeight ? (height - textHeight) * 0.5f : 0.0f;
}

/** Two-state checkbox style control with an optional label. */
final class UiToggle : UiWidget
{
    string label;
    bool checked;
    UiTextStyle style;
    float[4] fillColor;
    float[4] borderColor;
    float[4] accentColor;
    float[4] textColor;
    void delegate(bool) onChanged;

    this(string label, bool checked = false, float x = 0.0f, float y = 0.0f, float width = 0.0f, float height = controlHeight, UiTextStyle style = UiTextStyle.medium)
    {
        super(x, y, width, height);
        this.label = label;
        this.checked = checked;
        this.style = style;
        fillColor = cast(float[4])defaultFillColor;
        borderColor = cast(float[4])defaultBorderColor;
        accentColor = cast(float[4])defaultAccentColor;
        textColor = cast(float[4])defaultTextColor;
    }

protected:
    override UiLayoutSize measureSelf(ref UiLayoutContext context)
    {
        const labelWidth = label.length == 0 ? 0.0f : textWidth(context, style, label) + controlGap;
        const measuredWidth = preferredWidth > 0.0f ? preferredWidth : controlHeight + labelWidth;
        const measuredHeight = preferredHeight > 0.0f ? preferredHeight : max(controlHeight, textHeight(context, style));
        setLayoutHint(measuredWidth, measuredHeight, measuredWidth, measuredHeight, measuredWidth, measuredHeight);
        return UiLayoutSize(measuredWidth, measuredHeight);
    }

    override void renderSelf(ref UiRenderContext context)
    {
        const boxSize = height < controlHeight ? height : controlHeight;
        const boxTop = (height - boxSize) * 0.5f;
        appendSurfaceFrame(context, 0.0f, boxTop, boxSize, boxTop + boxSize, fillColor, borderColor, context.depthBase);
        if (checked)
            appendSurfaceFrame(context, 5.0f, boxTop + 5.0f, boxSize - 5.0f, boxTop + boxSize - 5.0f, accentColor, accentColor, context.depthBase - 0.001f, true, false);

        if (label.length != 0)
        {
            const atlasHeight = fallbackTextHeight;
            appendTextLine(context, style, label, boxSize + controlGap, centeredTextY(height, atlasHeight), textColor, context.depthBase - 0.002f);
        }
    }

    override bool handlePointerEvent(ref UiPointerEvent event)
    {
        if (event.kind != UiPointerEventKind.buttonDown || event.button != 1)
            return false;

        checked = !checked;
        if (onChanged !is null)
            onChanged(checked);
        return true;
    }
}

/** Horizontal numeric value selector. */
final class UiSlider : UiWidget
{
    string label;
    float minimum;
    float maximum;
    float value;
    UiTextStyle style;
    float[4] fillColor;
    float[4] borderColor;
    float[4] accentColor;
    float[4] textColor;
    void delegate(float) onChanged;
    private bool dragging;

    this(string label, float minimum, float maximum, float value, float x = 0.0f, float y = 0.0f, float width = 220.0f, float height = controlHeight, UiTextStyle style = UiTextStyle.medium)
    {
        super(x, y, width, height);
        this.label = label;
        this.minimum = minimum;
        this.maximum = maximum > minimum ? maximum : minimum + 1.0f;
        this.value = clampFloat(value, this.minimum, this.maximum);
        this.style = style;
        fillColor = cast(float[4])defaultFillColor;
        borderColor = cast(float[4])defaultBorderColor;
        accentColor = cast(float[4])defaultAccentColor;
        textColor = cast(float[4])defaultTextColor;
    }

    void setValue(float newValue)
    {
        value = clampFloat(newValue, minimum, maximum);
        if (onChanged !is null)
            onChanged(value);
    }

    override bool dispatchPointerEvent(ref UiPointerEvent event)
    {
        if (dragging)
            return handlePointerEvent(event);

        return super.dispatchPointerEvent(event);
    }

protected:
    override UiLayoutSize measureSelf(ref UiLayoutContext context)
    {
        const labelText = format("%s %.2f", label, value);
        const measuredWidth = preferredWidth > 0.0f ? preferredWidth : max(180.0f, textWidth(context, style, labelText) + 80.0f);
        const measuredHeight = preferredHeight > 0.0f ? preferredHeight : controlHeight;
        setLayoutHint(measuredWidth, measuredHeight, measuredWidth, measuredHeight, float.max, measuredHeight, 1.0f, 0.0f);
        return UiLayoutSize(measuredWidth, measuredHeight);
    }

    override void renderSelf(ref UiRenderContext context)
    {
        const labelText = format("%s %.2f", label, value);
        appendTextLine(context, style, labelText, 0.0f, 0.0f, textColor, context.depthBase - 0.002f);

        const trackTop = height - 9.0f;
        const trackBottom = height - 3.0f;
        const ratio = (value - minimum) / (maximum - minimum);
        const fillRight = width * clampFloat(ratio, 0.0f, 1.0f);
        appendSurfaceFrame(context, 0.0f, trackTop, width, trackBottom, fillColor, borderColor, context.depthBase);
        appendQuad(context, 0.0f, trackTop, fillRight, trackBottom, context.depthBase - 0.001f, accentColor);
        appendSurfaceFrame(context, fillRight - 3.0f, trackTop - 4.0f, fillRight + 3.0f, trackBottom + 4.0f, accentColor, accentColor, context.depthBase - 0.002f);
    }

    override bool handlePointerEvent(ref UiPointerEvent event)
    {
        if (event.kind == UiPointerEventKind.buttonUp && event.button == 1)
        {
            dragging = false;
            return true;
        }

        if (event.kind == UiPointerEventKind.move)
        {
            if (!dragging)
                return false;

            updateValueFromPointer(event.x);
            return true;
        }

        if (event.kind != UiPointerEventKind.buttonDown || event.button != 1)
            return dragging;

        dragging = true;
        updateValueFromPointer(event.x);
        return true;
    }

    void updateValueFromPointer(float pointerX)
    {
        const ratio = width > 0.0f ? clampFloat(pointerX / width, 0.0f, 1.0f) : 0.0f;
        setValue(minimum + (maximum - minimum) * ratio);
    }
}

/** Compact option selector that cycles through available values on click. */
final class UiDropdown : UiWidget
{
    string label;
    string[] options;
    size_t selectedIndex;
    UiTextStyle style;
    float[4] fillColor;
    float[4] borderColor;
    float[4] textColor;
    void delegate(size_t, string) onChanged;

    this(string label, string[] options, size_t selectedIndex = 0, float x = 0.0f, float y = 0.0f, float width = 0.0f, float height = controlHeight, UiTextStyle style = UiTextStyle.medium)
    {
        super(x, y, width, height);
        this.label = label;
        this.options = options.dup;
        this.selectedIndex = options.length == 0 ? 0 : selectedIndex % options.length;
        this.style = style;
        fillColor = cast(float[4])defaultFillColor;
        borderColor = cast(float[4])defaultBorderColor;
        textColor = cast(float[4])defaultTextColor;
    }

    string selectedText() const
    {
        return options.length == 0 ? "" : options[selectedIndex];
    }

protected:
    override UiLayoutSize measureSelf(ref UiLayoutContext context)
    {
        float widest = textWidth(context, style, label);
        foreach (option; options)
            widest = max(widest, textWidth(context, style, option));

        const measuredWidth = preferredWidth > 0.0f ? preferredWidth : widest + controlPaddingX * 2.0f + 28.0f;
        const measuredHeight = preferredHeight > 0.0f ? preferredHeight : controlHeight;
        setLayoutHint(measuredWidth, measuredHeight, measuredWidth, measuredHeight, measuredWidth, measuredHeight);
        return UiLayoutSize(measuredWidth, measuredHeight);
    }

    override void renderSelf(ref UiRenderContext context)
    {
        appendSurfaceFrame(context, 0.0f, 0.0f, width, height, fillColor, borderColor, context.depthBase);
        appendTextLine(context, style, selectedText(), controlPaddingX, centeredTextY(height, fallbackTextHeight), textColor, context.depthBase - 0.002f);
        appendTextLine(context, style, "v", width - controlPaddingX - fallbackGlyphWidth, centeredTextY(height, fallbackTextHeight), cast(float[4])defaultMutedColor, context.depthBase - 0.002f);
    }

    override bool handlePointerEvent(ref UiPointerEvent event)
    {
        if (event.kind != UiPointerEventKind.buttonDown || event.button != 1 || options.length == 0)
            return false;

        selectedIndex = (selectedIndex + 1) % options.length;
        if (onChanged !is null)
            onChanged(selectedIndex, selectedText());
        return true;
    }
}

/** Single-line text value field with focus state. */
final class UiTextField : UiWidget
{
    string text;
    string placeholder;
    bool focused;
    UiTextStyle style;
    float[4] fillColor;
    float[4] borderColor;
    float[4] focusedBorderColor;
    float[4] textColor;
    void delegate(string) onChanged;

    this(string text = "", string placeholder = "", float x = 0.0f, float y = 0.0f, float width = 180.0f, float height = controlHeight, UiTextStyle style = UiTextStyle.medium)
    {
        super(x, y, width, height);
        this.text = text;
        this.placeholder = placeholder;
        this.style = style;
        fillColor = cast(float[4])defaultFillColor;
        borderColor = cast(float[4])defaultBorderColor;
        focusedBorderColor = cast(float[4])defaultAccentColor;
        textColor = cast(float[4])defaultTextColor;
    }

    void setText(string newText)
    {
        text = newText;
        if (onChanged !is null)
            onChanged(text);
    }

protected:
    override UiLayoutSize measureSelf(ref UiLayoutContext context)
    {
        const sampleText = text.length != 0 ? text : placeholder;
        const measuredWidth = preferredWidth > 0.0f ? preferredWidth : max(140.0f, textWidth(context, style, sampleText) + controlPaddingX * 2.0f);
        const measuredHeight = preferredHeight > 0.0f ? preferredHeight : controlHeight;
        setLayoutHint(measuredWidth, measuredHeight, measuredWidth, measuredHeight, float.max, measuredHeight, 1.0f, 0.0f);
        return UiLayoutSize(measuredWidth, measuredHeight);
    }

    override void renderSelf(ref UiRenderContext context)
    {
        const shownText = text.length != 0 ? text : placeholder;
        const color = text.length != 0 ? textColor : cast(float[4])defaultMutedColor;
        appendSurfaceFrame(context, 0.0f, 0.0f, width, height, fillColor, focused ? focusedBorderColor : borderColor, context.depthBase);
        appendTextLine(context, style, shownText, controlPaddingX, centeredTextY(height, fallbackTextHeight), color, context.depthBase - 0.002f);
    }

    override bool handlePointerEvent(ref UiPointerEvent event)
    {
        if (event.kind != UiPointerEventKind.buttonDown || event.button != 1)
            return false;

        focused = true;
        return true;
    }
}

@("UiToggle flips state and emits changes")
unittest
{
    auto toggle = new UiToggle("Enabled", false, 0.0f, 0.0f, 120.0f, 28.0f);
    bool changed;
    toggle.onChanged = (value) { changed = value; };

    UiPointerEvent event;
    event.kind = UiPointerEventKind.buttonDown;
    event.button = 1;
    event.x = 8.0f;
    event.y = 8.0f;

    assert(toggle.dispatchPointerEvent(event));
    assert(toggle.checked);
    assert(changed);
}

@("UiSlider maps pointer position to value")
unittest
{
    auto slider = new UiSlider("Scale", 0.0f, 10.0f, 0.0f, 0.0f, 0.0f, 200.0f, 28.0f);

    UiPointerEvent event;
    event.kind = UiPointerEventKind.buttonDown;
    event.button = 1;
    event.x = 100.0f;
    event.y = 20.0f;

    assert(slider.dispatchPointerEvent(event));
    assert(slider.value > 4.9f && slider.value < 5.1f);
}

@("UiSlider drags while pointer is captured")
unittest
{
    auto slider = new UiSlider("Scale", 0.0f, 10.0f, 0.0f, 0.0f, 0.0f, 200.0f, 28.0f);

    UiPointerEvent event;
    event.kind = UiPointerEventKind.buttonDown;
    event.button = 1;
    event.x = 10.0f;
    event.y = 20.0f;
    assert(slider.dispatchPointerEvent(event));

    event.kind = UiPointerEventKind.move;
    event.x = 150.0f;
    assert(slider.dispatchPointerEvent(event));
    assert(slider.value > 7.4f && slider.value < 7.6f);

    event.kind = UiPointerEventKind.buttonUp;
    assert(slider.dispatchPointerEvent(event));
}

@("UiDropdown cycles options")
unittest
{
    auto dropdown = new UiDropdown("Theme", ["midnight", "classic"], 0, 0.0f, 0.0f, 160.0f, 28.0f);

    UiPointerEvent event;
    event.kind = UiPointerEventKind.buttonDown;
    event.button = 1;
    event.x = 20.0f;
    event.y = 12.0f;

    assert(dropdown.dispatchPointerEvent(event));
    assert(dropdown.selectedText() == "classic");
}

@("UiTextField focuses and accepts programmatic text")
unittest
{
    auto field = new UiTextField("", "Name", 0.0f, 0.0f, 160.0f, 28.0f);

    UiPointerEvent event;
    event.kind = UiPointerEventKind.buttonDown;
    event.button = 1;
    event.x = 20.0f;
    event.y = 12.0f;

    assert(field.dispatchPointerEvent(event));
    assert(field.focused);
    field.setText("Player");
    assert(field.text == "Player");
}
