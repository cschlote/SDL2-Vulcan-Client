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

/** Two-state checkbox style control with an optional label.
 *
 * `UiToggle` is a retained control for boolean settings. A primary-button
 * click flips `checked` and emits `onChanged` with the new value.
 */
final class UiToggle : UiWidget
{
    /** Text rendered next to the toggle box. */
    string label;
    /** Current boolean state. */
    bool checked;
    /** Font style used for the optional label. */
    UiTextStyle style;
    /** Toggle box fill color. */
    float[4] fillColor;
    /** Toggle box border color. */
    float[4] borderColor;
    /** Color used for the checked indicator. */
    float[4] accentColor;
    /** Label text color. */
    float[4] textColor;
    /** Called after user interaction changes `checked`. */
    void delegate(bool) onChanged;

    /** Creates a retained two-state toggle.
     *
     * Params:
     *   label = Text rendered next to the toggle box.
     *   checked = Initial boolean state.
     *   x = Left edge in parent coordinates.
     *   y = Top edge in parent coordinates.
     *   width = Optional explicit width in pixels.
     *   height = Optional explicit height in pixels.
     *   style = Font style used for the label.
     */
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

/** Horizontal numeric value selector.
 *
 * `UiSlider` maps pointer position to a floating-point value in the configured
 * range. After button-down it keeps local pointer capture until button-up so
 * dragging remains stable even when the cursor leaves the original handle box.
 */
final class UiSlider : UiWidget
{
    /** Label prefix rendered with the current numeric value. */
    string label;
    /** Smallest selectable value. */
    float minimum;
    /** Largest selectable value. */
    float maximum;
    /** Current selected value. */
    float value;
    /** Font style used for the label and value. */
    UiTextStyle style;
    /** Track fill color. */
    float[4] fillColor;
    /** Track border color. */
    float[4] borderColor;
    /** Filled-track and handle color. */
    float[4] accentColor;
    /** Label text color. */
    float[4] textColor;
    /** Called after user interaction or `setValue` changes `value`. */
    void delegate(float) onChanged;
    private bool dragging;

    /** Creates a retained horizontal slider.
     *
     * Params:
     *   label = Label prefix rendered before the numeric value.
     *   minimum = Smallest selectable value.
     *   maximum = Largest selectable value; adjusted above `minimum` if needed.
     *   value = Initial value, clamped to the configured range.
     *   x = Left edge in parent coordinates.
     *   y = Top edge in parent coordinates.
     *   width = Optional explicit width in pixels.
     *   height = Optional explicit height in pixels.
     *   style = Font style used for the label and value.
     */
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

    /** Sets the slider value and emits `onChanged`. */
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

/** Compact option selector that cycles through available values on click.
 *
 * This is an intentionally small combo-box placeholder. It keeps the retained
 * control API generic while the UI engine does not yet have popups or menus.
 */
final class UiDropdown : UiWidget
{
    /** Logical label for the option group. */
    string label;
    /** Available selectable values. */
    string[] options;
    /** Index into `options` for the currently selected value. */
    size_t selectedIndex;
    /** Font style used for the selected value. */
    UiTextStyle style;
    /** Control fill color. */
    float[4] fillColor;
    /** Control border color. */
    float[4] borderColor;
    /** Selected value text color. */
    float[4] textColor;
    /** Called after user interaction selects a new value. */
    void delegate(size_t, string) onChanged;

    /** Creates a retained dropdown-style option selector.
     *
     * Params:
     *   label = Logical label for the option group.
     *   options = Available selectable values.
     *   selectedIndex = Initially selected option index.
     *   x = Left edge in parent coordinates.
     *   y = Top edge in parent coordinates.
     *   width = Optional explicit width in pixels.
     *   height = Optional explicit height in pixels.
     *   style = Font style used for the selected value.
     */
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

    /** Returns the selected option text, or an empty string without options. */
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

/** Single-line text value field with focus state.
 *
 * `UiTextField` currently stores and renders a single text value and can be
 * focused by pointer input. Keyboard editing is still an application/UI-engine
 * follow-up; programmatic updates use `setText`.
 */
final class UiTextField : UiWidget
{
    /** Current text value. */
    string text;
    /** Placeholder rendered when `text` is empty. */
    string placeholder;
    /** True after the field receives a primary-button click. */
    bool focused;
    /** Font style used for text and placeholder rendering. */
    UiTextStyle style;
    /** Field fill color. */
    float[4] fillColor;
    /** Field border color when not focused. */
    float[4] borderColor;
    /** Field border color when focused. */
    float[4] focusedBorderColor;
    /** Text color for non-placeholder content. */
    float[4] textColor;
    /** Called after `setText` changes `text`. */
    void delegate(string) onChanged;

    /** Creates a retained single-line text field.
     *
     * Params:
     *   text = Initial text value.
     *   placeholder = Text shown when the value is empty.
     *   x = Left edge in parent coordinates.
     *   y = Top edge in parent coordinates.
     *   width = Optional explicit width in pixels.
     *   height = Optional explicit height in pixels.
     *   style = Font style used for rendering.
     */
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

    /** Sets the field text and emits `onChanged`. */
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
