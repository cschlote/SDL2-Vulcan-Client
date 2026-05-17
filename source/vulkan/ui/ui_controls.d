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

import std.algorithm : max, min;
import std.format : format;

import vulkan.font.font_legacy : measureTextWidth;
import vulkan.ui.ui_context : UiRenderContext, UiTextStyle;
import vulkan.ui.ui_cursor : UiCursorKind;
import vulkan.ui.ui_event : UiKeyCode, UiKeyEvent, UiKeyEventKind, UiPointerEvent, UiPointerEventKind, UiTextInputEvent;
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

private float textWidth(ref UiRenderContext context, UiTextStyle style, string text)
{
    auto atlas = context.atlasFor(style);
    return atlas is null ? cast(float)text.length * fallbackGlyphWidth : measureTextWidth(*atlas, text);
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
        focusable = true;
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

    override bool handleKeyEvent(ref UiKeyEvent event)
    {
        if (event.kind != UiKeyEventKind.keyDown || event.key != UiKeyCode.enter)
            return false;

        checked = !checked;
        if (onChanged !is null)
            onChanged(checked);
        return true;
    }

    override UiCursorKind cursorSelf(float localX, float localY)
    {
        return UiCursorKind.pointer;
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
    /** Called when a pointer drag or direct pointer click commits the value. */
    void delegate(float) onCommitted;
    private bool dragging;
    private bool commitPending;

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
        focusable = true;
        fillColor = cast(float[4])defaultFillColor;
        borderColor = cast(float[4])defaultBorderColor;
        accentColor = cast(float[4])defaultAccentColor;
        textColor = cast(float[4])defaultTextColor;
    }

    /** Sets the slider value and emits `onChanged` when it changed. */
    bool setValue(float newValue)
    {
        const clampedValue = clampFloat(newValue, minimum, maximum);
        if (clampedValue == value)
            return false;

        value = clampedValue;
        if (onChanged !is null)
            onChanged(value);
        return true;
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
            const shouldCommit = dragging && commitPending;
            dragging = false;
            commitPending = false;
            if (shouldCommit && onCommitted !is null)
                onCommitted(value);
            return true;
        }

        if (event.kind == UiPointerEventKind.move)
        {
            if (!dragging)
                return false;

            commitPending = updateValueFromPointer(event.x) || commitPending;
            return true;
        }

        if (event.kind != UiPointerEventKind.buttonDown || event.button != 1)
            return dragging;

        dragging = true;
        commitPending = updateValueFromPointer(event.x);
        return true;
    }

    override UiCursorKind cursorSelf(float localX, float localY)
    {
        return UiCursorKind.pointer;
    }

    bool updateValueFromPointer(float pointerX)
    {
        const ratio = width > 0.0f ? clampFloat(pointerX / width, 0.0f, 1.0f) : 0.0f;
        return setValue(minimum + (maximum - minimum) * ratio);
    }

    override bool handleKeyEvent(ref UiKeyEvent event)
    {
        if (event.kind != UiKeyEventKind.keyDown)
            return false;

        const step = (maximum - minimum) * 0.05f;
        final switch (event.key)
        {
            case UiKeyCode.left:
            case UiKeyCode.down:
                setValue(value - step);
                return true;
            case UiKeyCode.right:
            case UiKeyCode.up:
                setValue(value + step);
                return true;
            case UiKeyCode.home:
                setValue(minimum);
                return true;
            case UiKeyCode.end:
                setValue(maximum);
                return true;
            case UiKeyCode.backspace:
            case UiKeyCode.delete_:
            case UiKeyCode.enter:
            case UiKeyCode.escape:
            case UiKeyCode.tab:
            case UiKeyCode.unknown:
                return false;
        }
    }
}

/** Horizontal tab selector for switching between related pages. */
final class UiTabBar : UiWidget
{
    /** Tab labels in display order. */
    string[] tabs;
    /** Index into `tabs` for the currently active page. */
    size_t selectedIndex;
    /** Font style used for tab labels. */
    UiTextStyle style;
    /** Tab bar fill color. */
    float[4] fillColor;
    /** Tab bar border color. */
    float[4] borderColor;
    /** Active tab fill color. */
    float[4] selectedColor;
    /** Tab text color. */
    float[4] textColor;
    /** Called after user interaction selects a different tab. */
    void delegate(size_t, string) onChanged;

    /** Creates a retained horizontal tab bar. */
    this(string[] tabs, size_t selectedIndex = 0, float x = 0.0f, float y = 0.0f, float width = 0.0f, float height = controlHeight, UiTextStyle style = UiTextStyle.medium)
    {
        super(x, y, width, height);
        this.tabs = tabs.dup;
        this.selectedIndex = tabs.length == 0 ? 0 : selectedIndex % tabs.length;
        this.style = style;
        focusable = true;
        fillColor = cast(float[4])defaultFillColor;
        borderColor = cast(float[4])defaultBorderColor;
        selectedColor = cast(float[4])defaultAccentColor;
        textColor = cast(float[4])defaultTextColor;
    }

    /** Selects a tab by index and emits `onChanged` when the active tab changes. */
    void selectIndex(size_t index)
    {
        if (tabs.length == 0)
            return;

        const normalizedIndex = index % tabs.length;
        if (selectedIndex == normalizedIndex)
            return;

        selectedIndex = normalizedIndex;
        if (onChanged !is null)
            onChanged(selectedIndex, tabs[selectedIndex]);
    }

protected:
    override UiLayoutSize measureSelf(ref UiLayoutContext context)
    {
        float totalWidth = 0.0f;
        foreach (tab; tabs)
            totalWidth += textWidth(context, style, tab) + controlPaddingX * 2.0f;

        const measuredWidth = preferredWidth > 0.0f ? preferredWidth : totalWidth;
        const measuredHeight = preferredHeight > 0.0f ? preferredHeight : controlHeight;
        setLayoutHint(measuredWidth, measuredHeight, measuredWidth, measuredHeight, float.max, measuredHeight, 1.0f, 0.0f);
        return UiLayoutSize(measuredWidth, measuredHeight);
    }

    override void renderSelf(ref UiRenderContext context)
    {
        appendSurfaceFrame(context, 0.0f, 0.0f, width, height, fillColor, borderColor, context.depthBase);
        if (tabs.length == 0)
            return;

        const tabWidth = width / cast(float)tabs.length;
        foreach (index, tab; tabs)
        {
            const left = cast(float)index * tabWidth;
            const right = index + 1 == tabs.length ? width : left + tabWidth;
            if (index == selectedIndex)
                appendQuad(context, left + 1.0f, 1.0f, right - 1.0f, height - 1.0f, context.depthBase - 0.001f, selectedColor);
            appendTextLine(context, style, tab, left + controlPaddingX, centeredTextY(height, fallbackTextHeight), textColor, context.depthBase - 0.002f);
        }
    }

    override bool handlePointerEvent(ref UiPointerEvent event)
    {
        if (event.kind != UiPointerEventKind.buttonDown || event.button != 1 || tabs.length == 0)
            return false;

        const localX = event.x - x;
        if (localX < 0.0f)
            return false;

        const tabWidth = width / cast(float)tabs.length;
        const index = cast(size_t)(localX / tabWidth);
        if (index >= tabs.length)
            return false;

        selectIndex(index);
        return true;
    }

    override bool handleKeyEvent(ref UiKeyEvent event)
    {
        if (event.kind != UiKeyEventKind.keyDown || tabs.length == 0)
            return false;

        final switch (event.key)
        {
            case UiKeyCode.left:
                selectIndex(selectedIndex == 0 ? tabs.length - 1 : selectedIndex - 1);
                return true;
            case UiKeyCode.right:
                selectIndex(selectedIndex + 1);
                return true;
            case UiKeyCode.up:
            case UiKeyCode.down:
                return false;
            case UiKeyCode.home:
                selectIndex(0);
                return true;
            case UiKeyCode.end:
                selectIndex(tabs.length - 1);
                return true;
            case UiKeyCode.backspace:
            case UiKeyCode.delete_:
            case UiKeyCode.enter:
            case UiKeyCode.escape:
            case UiKeyCode.tab:
            case UiKeyCode.unknown:
                return false;
        }
    }

    override UiCursorKind cursorSelf(float localX, float localY)
    {
        return tabs.length == 0 ? UiCursorKind.default_ : UiCursorKind.pointer;
    }
}

/** Compact option selector that requests a transient popup list on click. */
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
    /** Called when the dropdown should open a popup near the supplied screen-space anchor. */
    void delegate(UiDropdown, float, float, float, float) onOpenRequested;

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
        focusable = true;
        fillColor = cast(float[4])defaultFillColor;
        borderColor = cast(float[4])defaultBorderColor;
        textColor = cast(float[4])defaultTextColor;
    }

    /** Returns the selected option text, or an empty string without options. */
    string selectedText() const
    {
        return options.length == 0 ? "" : options[selectedIndex];
    }

    /** Selects an option by index and emits `onChanged` when the value changes. */
    void selectIndex(size_t index)
    {
        if (options.length == 0)
            return;

        const normalizedIndex = index % options.length;
        if (selectedIndex == normalizedIndex)
            return;

        selectedIndex = normalizedIndex;
        emitChanged();
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

        if (onOpenRequested !is null)
        {
            const anchorX = event.screenX - event.x + x;
            const anchorY = event.screenY - event.y + y;
            onOpenRequested(this, anchorX, anchorY, width, height);
        }
        return true;
    }

    override UiCursorKind cursorSelf(float localX, float localY)
    {
        return options.length == 0 ? UiCursorKind.default_ : UiCursorKind.pointer;
    }

private:
    void emitChanged()
    {
        if (onChanged !is null)
            onChanged(selectedIndex, selectedText());
    }
}

/** Selectable list of text rows for dropdowns and simple choice panels. */
final class UiListBox : UiWidget
{
    /** Available selectable values. */
    string[] options;
    /** Index into `options` for the currently selected value. */
    size_t selectedIndex;
    /** Height of one selectable row in pixels. */
    float rowHeight;
    /** Font style used for row text. */
    UiTextStyle style;
    /** List background color. */
    float[4] fillColor;
    /** List border color. */
    float[4] borderColor;
    /** Selected row background color. */
    float[4] selectedColor;
    /** Row text color. */
    float[4] textColor;
    /** Called after user interaction selects a new value. */
    void delegate(size_t, string) onChanged;
    /** Called after a row is clicked, even when it is already selected. */
    void delegate(size_t, string) onActivated;

    /** Creates a retained list box with text rows. */
    this(string[] options, size_t selectedIndex = 0, float x = 0.0f, float y = 0.0f, float width = 0.0f, float height = 0.0f, UiTextStyle style = UiTextStyle.medium, float rowHeight = controlHeight)
    {
        super(x, y, width, height);
        this.options = options.dup;
        this.selectedIndex = options.length == 0 ? 0 : selectedIndex % options.length;
        this.style = style;
        this.rowHeight = rowHeight > 0.0f ? rowHeight : controlHeight;
        focusable = true;
        fillColor = cast(float[4])defaultFillColor;
        borderColor = cast(float[4])defaultBorderColor;
        selectedColor = cast(float[4])defaultAccentColor;
        textColor = cast(float[4])defaultTextColor;
    }

    /** Returns the selected option text, or an empty string without options. */
    string selectedText() const
    {
        return options.length == 0 ? "" : options[selectedIndex];
    }

    /** Selects an option by index and emits `onChanged` when the value changes. */
    void selectIndex(size_t index)
    {
        if (options.length == 0)
            return;

        const normalizedIndex = index % options.length;
        if (selectedIndex == normalizedIndex)
            return;

        selectedIndex = normalizedIndex;
        if (onChanged !is null)
            onChanged(selectedIndex, selectedText());
    }

protected:
    override UiLayoutSize measureSelf(ref UiLayoutContext context)
    {
        float widest = 0.0f;
        foreach (option; options)
            widest = max(widest, textWidth(context, style, option));

        const naturalWidth = widest + controlPaddingX * 2.0f;
        const naturalHeight = cast(float)options.length * rowHeight;
        const measuredWidth = preferredWidth > 0.0f ? preferredWidth : naturalWidth;
        const measuredHeight = preferredHeight > 0.0f ? preferredHeight : naturalHeight;
        setLayoutHint(measuredWidth, measuredHeight, measuredWidth, measuredHeight, float.max, measuredHeight, 1.0f, 0.0f);
        return UiLayoutSize(measuredWidth, measuredHeight);
    }

    override void renderSelf(ref UiRenderContext context)
    {
        appendSurfaceFrame(context, 0.0f, 0.0f, width, height, fillColor, borderColor, context.depthBase);

        foreach (index, option; options)
        {
            const top = cast(float)index * rowHeight;
            const bottom = top + rowHeight;
            if (index == selectedIndex)
                appendQuad(context, 1.0f, top + 1.0f, width - 1.0f, bottom - 1.0f, context.depthBase - 0.001f, selectedColor);
            appendTextLine(context, style, option, controlPaddingX, top + centeredTextY(rowHeight, fallbackTextHeight), textColor, context.depthBase - 0.002f);
        }
    }

    override bool handlePointerEvent(ref UiPointerEvent event)
    {
        if (event.kind != UiPointerEventKind.buttonDown || event.button != 1 || options.length == 0)
            return false;

        const localY = event.y - y;
        if (localY < 0.0f)
            return false;

        const rowIndex = cast(size_t)(localY / rowHeight);
        if (rowIndex >= options.length)
            return false;

        selectIndex(rowIndex);
        if (onActivated !is null)
            onActivated(rowIndex, options[rowIndex]);
        return true;
    }

    override bool handleKeyEvent(ref UiKeyEvent event)
    {
        if (event.kind != UiKeyEventKind.keyDown || options.length == 0)
            return false;

        final switch (event.key)
        {
            case UiKeyCode.left:
            case UiKeyCode.up:
                selectIndex(selectedIndex == 0 ? options.length - 1 : selectedIndex - 1);
                return true;
            case UiKeyCode.right:
            case UiKeyCode.down:
                selectIndex(selectedIndex + 1);
                return true;
            case UiKeyCode.home:
                selectIndex(0);
                return true;
            case UiKeyCode.end:
                selectIndex(options.length - 1);
                return true;
            case UiKeyCode.enter:
                if (onActivated !is null)
                    onActivated(selectedIndex, selectedText());
                return true;
            case UiKeyCode.backspace:
            case UiKeyCode.delete_:
            case UiKeyCode.escape:
            case UiKeyCode.tab:
            case UiKeyCode.unknown:
                return false;
        }
    }

    override UiCursorKind cursorSelf(float localX, float localY)
    {
        return options.length == 0 ? UiCursorKind.default_ : UiCursorKind.pointer;
    }
}

/** Single-line text value field with focus state.
 *
 * `UiTextField` stores, renders, and edits a single UTF-8 text value. It is
 * focusable and accepts platform text input while it owns keyboard focus.
 */
final class UiTextField : UiWidget
{
    /** Current text value. */
    string text;
    /** Placeholder rendered when `text` is empty. */
    string placeholder;
    /** Cursor byte index inside `text`. */
    size_t cursorIndex;
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
        this.cursorIndex = text.length;
        focusable = true;
        fillColor = cast(float[4])defaultFillColor;
        borderColor = cast(float[4])defaultBorderColor;
        focusedBorderColor = cast(float[4])defaultAccentColor;
        textColor = cast(float[4])defaultTextColor;
    }

    /** Sets the field text and emits `onChanged`. */
    void setText(string newText)
    {
        text = newText;
        cursorIndex = min(cursorIndex, text.length);
        if (onChanged !is null)
            onChanged(text);
    }

    /** Moves the cursor to the end of the current text. */
    void moveCursorToEnd()
    {
        cursorIndex = text.length;
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
        if (focused)
        {
            const cursorText = cursorIndex > 0 ? text[0 .. cursorIndex] : "";
            const cursorX = min(width - controlPaddingX, controlPaddingX + textWidth(context, style, cursorText));
            appendQuad(context, cursorX, 5.0f, cursorX + 1.0f, height - 5.0f, context.depthBase - 0.003f, focusedBorderColor);
        }
    }

    override bool handlePointerEvent(ref UiPointerEvent event)
    {
        if (event.kind != UiPointerEventKind.buttonDown || event.button != 1)
            return false;

        focused = true;
        moveCursorToEnd();
        return true;
    }

    override UiCursorKind cursorSelf(float localX, float localY)
    {
        return UiCursorKind.text;
    }

    override bool handleTextInputEvent(ref UiTextInputEvent event)
    {
        if (event.text.length == 0)
            return false;

        text = text[0 .. cursorIndex] ~ event.text ~ text[cursorIndex .. $];
        cursorIndex += event.text.length;
        emitChanged();
        return true;
    }

    override bool handleKeyEvent(ref UiKeyEvent event)
    {
        if (event.kind != UiKeyEventKind.keyDown)
            return false;

        final switch (event.key)
        {
            case UiKeyCode.backspace:
                if (cursorIndex == 0)
                    return true;
                const previous = previousUtf8Boundary(text, cursorIndex);
                text = text[0 .. previous] ~ text[cursorIndex .. $];
                cursorIndex = previous;
                emitChanged();
                return true;
            case UiKeyCode.delete_:
                if (cursorIndex >= text.length)
                    return true;
                const next = nextUtf8Boundary(text, cursorIndex);
                text = text[0 .. cursorIndex] ~ text[next .. $];
                emitChanged();
                return true;
            case UiKeyCode.left:
                cursorIndex = previousUtf8Boundary(text, cursorIndex);
                return true;
            case UiKeyCode.right:
                cursorIndex = nextUtf8Boundary(text, cursorIndex);
                return true;
            case UiKeyCode.up:
            case UiKeyCode.down:
                return false;
            case UiKeyCode.home:
                cursorIndex = 0;
                return true;
            case UiKeyCode.end:
                cursorIndex = text.length;
                return true;
            case UiKeyCode.enter:
            case UiKeyCode.escape:
            case UiKeyCode.tab:
            case UiKeyCode.unknown:
                return false;
        }
    }

private:
    void emitChanged()
    {
        if (onChanged !is null)
            onChanged(text);
    }

    static size_t previousUtf8Boundary(string value, size_t index)
    {
        if (index == 0)
            return 0;

        auto pos = min(index, value.length) - 1;
        while (pos > 0 && isUtf8Continuation(value[pos]))
            --pos;
        return pos;
    }

    static size_t nextUtf8Boundary(string value, size_t index)
    {
        if (index >= value.length)
            return value.length;

        auto pos = index + 1;
        while (pos < value.length && isUtf8Continuation(value[pos]))
            ++pos;
        return pos;
    }

    static bool isUtf8Continuation(char value)
    {
        return (cast(ubyte)value & 0xC0) == 0x80;
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

    UiKeyEvent keyEvent;
    keyEvent.kind = UiKeyEventKind.keyDown;
    keyEvent.key = UiKeyCode.enter;
    assert(toggle.dispatchKeyEvent(keyEvent));
    assert(!toggle.checked);
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

    UiKeyEvent keyEvent;
    keyEvent.kind = UiKeyEventKind.keyDown;
    keyEvent.key = UiKeyCode.end;
    assert(slider.dispatchKeyEvent(keyEvent));
    assert(slider.value == 10.0f);
}

@("UiSlider drags while pointer is captured")
unittest
{
    auto slider = new UiSlider("Scale", 0.0f, 10.0f, 0.0f, 0.0f, 0.0f, 200.0f, 28.0f);
    uint commits;
    slider.onCommitted = (value) { ++commits; };

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
    assert(commits == 1);
}

@("UiDropdown requests popup anchors and selects by index")
unittest
{
    auto dropdown = new UiDropdown("Theme", ["midnight", "classic"], 0, 0.0f, 0.0f, 160.0f, 28.0f);
    assert(dropdown.focusable);

    bool opened;
    float anchorX;
    float anchorY;
    dropdown.onOpenRequested = (source, x, y, width, height)
    {
        opened = source is dropdown;
        anchorX = x;
        anchorY = y;
        assert(width == 160.0f);
        assert(height == 28.0f);
    };

    UiPointerEvent event;
    event.kind = UiPointerEventKind.buttonDown;
    event.button = 1;
    event.x = 20.0f;
    event.y = 12.0f;
    event.screenX = 120.0f;
    event.screenY = 72.0f;

    assert(dropdown.dispatchPointerEvent(event));
    assert(opened);
    assert(anchorX == 100.0f);
    assert(anchorY == 60.0f);
    dropdown.selectIndex(1);
    assert(dropdown.selectedText() == "classic");
}

@("UiTabBar selects clicked tabs")
unittest
{
    auto tabBar = new UiTabBar(["Display", "UI", "Audio"], 0, 0.0f, 0.0f, 240.0f, 28.0f);
    size_t changedIndex;
    string changedValue;
    tabBar.onChanged = (index, value)
    {
        changedIndex = index;
        changedValue = value;
    };

    UiPointerEvent event;
    event.kind = UiPointerEventKind.buttonDown;
    event.button = 1;
    event.x = 120.0f;
    event.y = 12.0f;

    assert(tabBar.dispatchPointerEvent(event));
    assert(tabBar.selectedIndex == 1);
    assert(changedIndex == 1);
    assert(changedValue == "UI");

    UiKeyEvent keyEvent;
    keyEvent.kind = UiKeyEventKind.keyDown;
    keyEvent.key = UiKeyCode.right;
    assert(tabBar.dispatchKeyEvent(keyEvent));
    assert(tabBar.selectedIndex == 2);

    keyEvent.key = UiKeyCode.home;
    assert(tabBar.dispatchKeyEvent(keyEvent));
    assert(tabBar.selectedIndex == 0);
}

@("UiListBox selects clicked rows")
unittest
{
    auto list = new UiListBox(["Alpha", "Beta", "Gamma"], 0, 0.0f, 0.0f, 160.0f, 84.0f);
    size_t changedIndex;
    string changedValue;
    bool activated;
    size_t activatedIndex;
    string activatedValue;
    list.onChanged = (index, value)
    {
        changedIndex = index;
        changedValue = value;
    };
    list.onActivated = (index, value)
    {
        activated = true;
        activatedIndex = index;
        activatedValue = value;
    };

    UiPointerEvent event;
    event.kind = UiPointerEventKind.buttonDown;
    event.button = 1;
    event.x = 12.0f;
    event.y = 42.0f;

    assert(list.dispatchPointerEvent(event));
    assert(list.selectedIndex == 1);
    assert(list.selectedText() == "Beta");
    assert(changedIndex == 1);
    assert(changedValue == "Beta");
    assert(activated);
    assert(activatedIndex == 1);
    assert(activatedValue == "Beta");

    UiKeyEvent keyEvent;
    keyEvent.kind = UiKeyEventKind.keyDown;
    keyEvent.key = UiKeyCode.down;
    assert(list.dispatchKeyEvent(keyEvent));
    assert(list.selectedIndex == 2);

    keyEvent.key = UiKeyCode.enter;
    assert(list.dispatchKeyEvent(keyEvent));
    assert(activatedIndex == 2);
    assert(activatedValue == "Gamma");
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

@("UiTextField edits focused text with key and text input events")
unittest
{
    auto field = new UiTextField("AC", "Name", 0.0f, 0.0f, 160.0f, 28.0f);
    string changed;
    field.onChanged = (value) { changed = value; };
    field.setFocused(true);
    field.cursorIndex = 1;

    UiTextInputEvent textEvent;
    textEvent.text = "B";
    assert(field.dispatchTextInputEvent(textEvent));
    assert(field.text == "ABC");
    assert(field.cursorIndex == 2);
    assert(changed == "ABC");

    UiKeyEvent keyEvent;
    keyEvent.kind = UiKeyEventKind.keyDown;
    keyEvent.key = UiKeyCode.backspace;
    assert(field.dispatchKeyEvent(keyEvent));
    assert(field.text == "AC");
    assert(field.cursorIndex == 1);

    keyEvent.key = UiKeyCode.delete_;
    assert(field.dispatchKeyEvent(keyEvent));
    assert(field.text == "A");
    assert(field.cursorIndex == 1);
}
