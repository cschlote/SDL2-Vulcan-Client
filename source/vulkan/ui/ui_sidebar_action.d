/** Sidebar launcher action widget.
 *
 * This module defines a compact action row for left-edge launchers and dock
 * bars. Unlike a generic centered button, the icon slot and expanded label
 * region stay separate and stable.
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.ui.ui_sidebar_action;

import logging : logLine;
import vulkan.ui.ui_context : UiRenderContext, UiTextStyle;
import vulkan.ui.ui_cursor : UiCursorKind;
import vulkan.ui.ui_event : UiKeyCode, UiKeyEvent, UiKeyEventKind, UiPointerEvent, UiPointerEventKind;
import vulkan.ui.ui_image : UiImage;
import vulkan.ui.ui_label : UiLabel;
import vulkan.ui.ui_layout_context : UiLayoutContext, UiLayoutSize;
import vulkan.ui.ui_widget : UiWidget;
import vulkan.ui.ui_widget_helpers : appendSurfaceFrame;

enum float sidebarActionIconSlotWidth = 32.0f;
enum float sidebarActionIconSize = 18.0f;
enum float sidebarActionLabelGap = 5.0f;
private immutable float[4] defaultSidebarActionActiveColor = [0.34f, 0.82f, 0.46f, 0.95f];

/** Fixed-icon-slot action row for sidebars and dock launchers. */
final class UiSidebarAction : UiWidget
{
    /** Visible label text. In compact mode this can be the short icon mnemonic. */
    string caption;
    /** Asset id used by the embedded icon widget. */
    string assetId;
    /** Button body fill color. */
    float[4] bodyColor;
    /** Button border color. */
    float[4] borderColor;
    /** Label text color. */
    float[4] textColor;
    /** Label font style. */
    UiTextStyle style;
    /** Fixed icon slot width. */
    float iconSlotWidth;
    /** Whether this action represents an active/open target. */
    bool active;
    /** Accent color for the active-state marker. */
    float[4] activeColor;
    /** Action callback. */
    void delegate() onClick;

    private UiImage icon;
    private UiLabel label;

    this(string caption, string assetId, float x, float y, float width, float height, float[4] bodyColor, float[4] borderColor, float[4] textColor, float[4] iconFillColor, UiTextStyle style = UiTextStyle.small, float iconSlotWidth = sidebarActionIconSlotWidth, float iconSize = sidebarActionIconSize)
    {
        super(x, y, width, height);
        this.caption = caption;
        this.assetId = assetId;
        this.bodyColor = bodyColor;
        this.borderColor = borderColor;
        this.textColor = textColor;
        this.style = style;
        this.iconSlotWidth = iconSlotWidth;
        activeColor = cast(float[4])defaultSidebarActionActiveColor;
        focusable = true;

        icon = new UiImage(iconSize, iconSize, iconFillColor, borderColor);
        icon.setAsset(assetId);
        label = new UiLabel(caption, 0.0f, 0.0f, style, textColor);
        super.add(icon);
        super.add(label);
    }

    /** Updates the visible action text. */
    void setCaption(string caption)
    {
        this.caption = caption;
        label.text = caption;
        preferredWidth = 0.0f;
        preferredHeight = 0.0f;
        minimumWidth = 0.0f;
        minimumHeight = 0.0f;
    }

    /** Updates the renderer-facing icon asset without rebuilding the action row. */
    void setIconAsset(string assetId)
    {
        this.assetId = assetId;
        icon.setAsset(assetId);
    }

    /** Updates the active marker shown by renderSelf. */
    void setActive(bool active)
    {
        this.active = active;
    }

    /** Updates the tooltip shown when the expanded label is not visible. */
    void setTooltip(string text)
    {
        tooltipText = text;
    }

    /** Activates the action from pointer or keyboard input. */
    void activate()
    {
        const logCaption = caption.length != 0 ? caption : tooltipText;
        logLine("UiSidebarAction click: ", logCaption);
        if (onClick !is null)
            onClick();
    }

protected:
    override UiLayoutSize measureSelf(ref UiLayoutContext context)
    {
        const iconSize = icon.measure(context);
        const labelSize = label.measure(context);
        const naturalWidth = iconSlotWidth + (caption.length == 0 ? 0.0f : sidebarActionLabelGap + labelSize.width);
        const naturalHeight = iconSize.height > labelSize.height ? iconSize.height : labelSize.height;
        const measuredWidth = preferredWidth > 0.0f ? preferredWidth : naturalWidth;
        const measuredHeight = preferredHeight > 0.0f ? preferredHeight : naturalHeight;
        minimumWidth = minimumWidth > 0.0f ? minimumWidth : iconSlotWidth;
        minimumHeight = minimumHeight > 0.0f ? minimumHeight : naturalHeight;
        preferredWidth = measuredWidth;
        preferredHeight = measuredHeight;
        maximumWidth = maximumWidth > 0.0f ? maximumWidth : naturalWidth;
        maximumHeight = maximumHeight > 0.0f ? maximumHeight : measuredHeight;
        return UiLayoutSize(measuredWidth, measuredHeight);
    }

    override void layoutSelf(ref UiLayoutContext context)
    {
        const iconSize = icon.measure(context);
        const labelSize = label.measure(context);
        label.visible = width >= iconSlotWidth + sidebarActionLabelGap + labelSize.width;
        icon.x = (iconSlotWidth - iconSize.width) * 0.5f;
        icon.y = height > iconSize.height ? (height - iconSize.height) * 0.5f : 0.0f;
        icon.width = iconSize.width;
        icon.height = iconSize.height;
        icon.layout(context);

        if (label.visible)
        {
            label.x = iconSlotWidth + sidebarActionLabelGap;
            label.y = height > labelSize.height ? (height - labelSize.height) * 0.5f : 0.0f;
            label.width = width > label.x ? width - label.x : 0.0f;
            label.height = labelSize.height;
            label.layout(context);
        }
    }

    override void renderSelf(ref UiRenderContext context)
    {
        appendSurfaceFrame(context, 0.0f, 0.0f, width, height, bodyColor, borderColor, context.depthBase);
        if (active)
            appendSurfaceFrame(context, 1.0f, 3.0f, 4.0f, height - 3.0f, activeColor, activeColor, context.depthBase - 0.0008f, true, false);
    }

    override UiCursorKind cursorSelf(float localX, float localY)
    {
        return UiCursorKind.pointer;
    }

    override string tooltipSelf(float localX, float localY)
    {
        return label.visible ? "" : tooltipText;
    }

    override bool handlePointerEvent(ref UiPointerEvent event)
    {
        if (event.kind != UiPointerEventKind.buttonDown || event.button != 1)
            return false;

        activate();
        event.actionActivated = true;
        return true;
    }

    override bool handleKeyEvent(ref UiKeyEvent event)
    {
        if (event.kind != UiKeyEventKind.keyDown || event.key != UiKeyCode.enter)
            return false;

        activate();
        event.actionActivated = true;
        return true;
    }
}

@("UiSidebarAction keeps icon and label in separate regions")
unittest
{
    auto action = new UiSidebarAction("Help", "sidebar/help", 0.0f, 0.0f, 112.0f, 32.0f, [0.0f, 0.0f, 0.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f], [0.2f, 0.6f, 1.0f, 1.0f]);

    UiLayoutContext context;
    action.layout(context);

    assert(action.children.length == 2);
    assert(cast(UiImage)action.children[0] !is null);
    assert(cast(UiLabel)action.children[1] !is null);
    assert(action.children[0].x >= 0.0f);
    assert(action.children[0].x + action.children[0].width <= sidebarActionIconSlotWidth);
    assert(action.children[1].x > sidebarActionIconSlotWidth);
    assert(action.children[1].visible);
}

@("UiSidebarAction exposes active-state marker flag")
unittest
{
    auto action = new UiSidebarAction("Help", "sidebar/help", 0.0f, 0.0f, 112.0f, 32.0f, [0.0f, 0.0f, 0.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f], [0.2f, 0.6f, 1.0f, 1.0f]);
    assert(!action.active);
    action.setActive(true);
    assert(action.active);
}

@("UiSidebarAction reports tooltip only when label is hidden")
unittest
{
    auto action = new UiSidebarAction("Help Desk", "sidebar/help", 0.0f, 0.0f, 32.0f, 32.0f, [0.0f, 0.0f, 0.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f], [0.2f, 0.6f, 1.0f, 1.0f]);
    action.setTooltip("Open Help Desk");

    UiLayoutContext context;
    action.layout(context);
    assert(action.tooltipAt(4.0f, 4.0f) == "Open Help Desk");

    action.width = 120.0f;
    action.setLayoutHint(120.0f, 32.0f, 120.0f, 32.0f, 120.0f, 32.0f, 0.0f, 0.0f);
    action.layout(context);
    assert(action.tooltipAt(4.0f, 4.0f).length == 0);
}

@("UiSidebarAction activates from Enter")
unittest
{
    auto action = new UiSidebarAction("Exit", "sidebar/exit", 0.0f, 0.0f, 44.0f, 32.0f, [0.0f, 0.0f, 0.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f], [1.0f, 1.0f, 1.0f, 1.0f], [1.0f, 0.2f, 0.2f, 1.0f]);
    bool clicked;
    action.onClick = () { clicked = true; };

    UiKeyEvent event;
    event.kind = UiKeyEventKind.keyDown;
    event.key = UiKeyCode.enter;

    assert(action.dispatchKeyEvent(event));
    assert(clicked);
    assert(event.actionActivated);
}
