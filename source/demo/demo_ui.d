/** Builds the demo application's retained UI and overlay geometry.
 *
 * Organizes the demo window stack, drag state, and per-window draw ranges that
 * keep the overlay geometry grouped by window during rendering. The concrete
 * demo UI is built here; reusable widget behavior belongs in source/vulkan/ui/.
 *
 * See_Also:
 *   source/vulkan/ui/
 *   source/vulkan/engine/renderer.d
 *   docs/demo-ui-plan.md
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 *
 * Layout test helpers below are demo-only widgets used to exercise the retained
 * layout engine.
 */
module demo.demo_ui;

import std.format : format;
import std.algorithm : canFind, max;
import std.conv : ConvException, to;

import demo.demo_settings : DemoSettings;
import logging : logLine;
import vulkan.font.font_legacy : FontAtlas;
import vulkan.ui.ui_button : UiButton;
import vulkan.ui.ui_context : UiRenderContext, UiTextStyle;
import vulkan.ui.ui_controls : UiDropdown, UiListBox, UiProgressBar, UiSlider, UiTabBar, UiTextField, UiToggle;
import vulkan.ui.ui_cursor : UiCursorKind;
import vulkan.ui.ui_event : UiKeyCode, UiKeyEvent, UiKeyEventKind, UiPointerEvent, UiPointerEventKind, UiResizeHandle;
import vulkan.ui.ui_geometry : UiOverlayGeometry;
import vulkan.ui.ui_label : UiLabel;
import vulkan.ui.ui_layout : UiContentBox, UiFrameBox, UiHBox, UiSeparator, UiSpacer, UiVBox;
import vulkan.ui.ui_layout_context : UiLayoutContext, UiLayoutSize;
import vulkan.ui.ui_screen : UiScreen;
import vulkan.ui.ui_widget : UiWidget;
import vulkan.ui.ui_widget_helpers : appendSurfaceFrame;
import vulkan.ui.ui_window : UiWindow;

enum DemoAudioPreviewKind
{
    ui,
    master,
    music,
    effects
}

private final class LayoutDemoProbeBox : UiWidget
{
    private float[4] fillColor;
    private float[4] borderColor;

    this(float width, float height, float[4] fillColor, float[4] borderColor)
    {
        super(0.0f, 0.0f, width, height);
        this.fillColor = fillColor;
        this.borderColor = borderColor;
    }

    override UiLayoutSize measureSelf(ref UiLayoutContext context)
    {
        setLayoutHint(preferredWidth, preferredHeight, preferredWidth, preferredHeight, preferredWidth, preferredHeight, 0.0f, 0.0f);
        return UiLayoutSize(preferredWidth, preferredHeight);
    }

    override void renderSelf(ref UiRenderContext context)
    {
        appendSurfaceFrame(context, 0.0f, 0.0f, width, height, fillColor, borderColor, context.depthBase);
    }

    override UiCursorKind cursorSelf(float localX, float localY)
    {
        return UiCursorKind.crosshair;
    }
}

/** Builds a retained layout demo window that can be spawned repeatedly. */
final class LayoutDemoWindow
{
    UiWindow window;
    UiVBox content;

    this(uint serial, void delegate() onClose = null, void delegate(float, float) onHeaderDragStart = null, void delegate(float, float) onHeaderDragMove = null, void delegate() onHeaderDragEnd = null, void delegate(UiResizeHandle) onResizeStart = null, void delegate(UiResizeHandle, float, float) onResizeMove = null, void delegate(UiResizeHandle) onResizeEnd = null)
    {
        this(serial, null, onClose, onHeaderDragStart, onHeaderDragMove, onHeaderDragEnd, onResizeStart, onResizeMove, onResizeEnd);
    }

    this(uint serial, void delegate(UiDropdown, float, float, float, float) onDropdownOpen, void delegate() onClose = null, void delegate(float, float) onHeaderDragStart = null, void delegate(float, float) onHeaderDragMove = null, void delegate() onHeaderDragEnd = null, void delegate(UiResizeHandle) onResizeStart = null, void delegate(UiResizeHandle, float, float) onResizeMove = null, void delegate(UiResizeHandle) onResizeEnd = null)
    {
        const windowTitle = format("Widget Demo #%u", serial);
        window = new UiWindow(windowTitle, 36.0f, 36.0f, testWindowWidth, testWindowHeight, [0.10f, 0.12f, 0.16f, 0.95f], [0.14f, 0.16f, 0.20f, 0.98f], [1.00f, 0.98f, 0.82f, 1.00f], true, true, true, 14.0f, 12.0f, 14.0f, 12.0f);

        content = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, 12.0f);

        auto layoutSectionBody = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, 10.0f);
        auto topRow = new UiHBox(0.0f, 0.0f, 0.0f, 0.0f, 10.0f);
        topRow.setLayoutHint(0.0f, 0.0f, 0.0f, 0.0f, float.max, 80.0f, 1.0f, 0.0f);
        topRow.add(new LayoutDemoProbeBox(88.0f, 42.0f, cast(float[4])probeFillA, cast(float[4])probeBorderA));
        topRow.add(new LayoutDemoProbeBox(120.0f, 58.0f, cast(float[4])probeFillB, cast(float[4])probeBorderB));
        topRow.add(new LayoutDemoProbeBox(66.0f, 74.0f, cast(float[4])probeFillC, cast(float[4])probeBorderC));
        layoutSectionBody.add(new UiLabel("Layout probes and container bounds", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpAccentColor));
        layoutSectionBody.add(topRow);
        layoutSectionBody.add(new UiSpacer(0.0f, 4.0f));
        auto contentBox = new UiContentBox(0.0f, 0.0f, 0.0f, 44.0f, 8.0f, 8.0f, 8.0f, 8.0f);
        contentBox.setLayoutHint(0.0f, 44.0f, 0.0f, 44.0f, float.max, 44.0f, 1.0f, 0.0f);
        contentBox.add(new LayoutDemoProbeBox(260.0f, 28.0f, cast(float[4])probeFillD, cast(float[4])probeBorderD));
        layoutSectionBody.add(contentBox);

        auto layoutSection = new UiFrameBox(0.0f, 0.0f, 0.0f, 164.0f, [0.11f, 0.13f, 0.18f, 0.92f], [0.24f, 0.58f, 0.80f, 1.00f], 10.0f, 8.0f, 10.0f, 8.0f);
        layoutSection.setLayoutHint(0.0f, 164.0f, 0.0f, 164.0f, float.max, 164.0f, 1.0f, 0.0f);
        layoutSection.add(layoutSectionBody);

        auto controlsBody = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, 8.0f);
        controlsBody.add(new UiLabel("Retained controls", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpAccentColor));
        auto controlsRowA = new UiHBox(0.0f, 0.0f, 0.0f, 0.0f, 12.0f);
        controlsRowA.setLayoutHint(0.0f, 28.0f, 0.0f, 28.0f, float.max, 28.0f, 1.0f, 0.0f);
        controlsRowA.add(new UiToggle("Enabled", true, 0.0f, 0.0f, 130.0f, 28.0f));
        auto modeDropdown = new UiDropdown("Mode", ["Alpha", "Beta", "Gamma"], 0, 0.0f, 0.0f, 150.0f, 28.0f);
        modeDropdown.onOpenRequested = onDropdownOpen;
        controlsRowA.add(modeDropdown);
        controlsBody.add(controlsRowA);
        auto controlsRowB = new UiHBox(0.0f, 0.0f, 0.0f, 0.0f, 12.0f);
        controlsRowB.setLayoutHint(0.0f, 34.0f, 0.0f, 34.0f, float.max, 34.0f, 1.0f, 0.0f);
        auto amountSlider = new UiSlider("Amount", 0.0f, 1.0f, 0.42f, 0.0f, 0.0f, 220.0f, 34.0f);
        controlsRowB.add(amountSlider);
        controlsRowB.add(new UiTextField("demo", "type here", 0.0f, 0.0f, 160.0f, 28.0f));
        controlsBody.add(controlsRowB);
        auto progressBar = new UiProgressBar("Progress", 0.0f, 1.0f, amountSlider.value, 0.0f, 0.0f, 0.0f, 24.0f);
        progressBar.setLayoutHint(0.0f, 24.0f, 0.0f, 24.0f, float.max, 24.0f, 1.0f, 0.0f);
        amountSlider.onChanged = (value) { progressBar.setValue(value); };
        controlsBody.add(progressBar);
        controlsBody.add(new UiSeparator());
        auto selectionRow = new UiHBox(0.0f, 0.0f, 0.0f, 0.0f, 12.0f);
        selectionRow.setLayoutHint(0.0f, 78.0f, 0.0f, 78.0f, float.max, 78.0f, 1.0f, 0.0f);
        auto listBox = new UiListBox(["Alpha", "Beta", "Gamma"], 1, 0.0f, 0.0f, 150.0f, 72.0f, UiTextStyle.medium, 24.0f);
        auto listSummary = new UiLabel("List selection: Beta", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpTextColor);
        listBox.onChanged = (index, value) { listSummary.text = format("List selection: %s", value); };
        selectionRow.add(listBox);
        selectionRow.add(listSummary);
        controlsBody.add(selectionRow);
        auto tabsRow = new UiHBox(0.0f, 0.0f, 0.0f, 0.0f, 12.0f);
        tabsRow.setLayoutHint(0.0f, 32.0f, 0.0f, 32.0f, float.max, 32.0f, 1.0f, 0.0f);
        auto demoTabs = new UiTabBar(["One", "Two", "Three"], 0, 0.0f, 0.0f, 240.0f, 28.0f);
        auto tabSummary = new UiLabel("Tab: One", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpTextColor);
        demoTabs.onChanged = (index, value) { tabSummary.text = format("Tab: %s", value); };
        tabsRow.add(demoTabs);
        tabsRow.add(tabSummary);
        controlsBody.add(tabsRow);
        controlsBody.add(new UiSeparator());
        auto actionRow = new UiHBox(0.0f, 0.0f, 0.0f, 0.0f, 12.0f);
        actionRow.setLayoutHint(0.0f, 32.0f, 0.0f, 32.0f, float.max, 32.0f, 1.0f, 0.0f);
        actionRow.add(new UiButton("Primary", 0.0f, 0.0f, 104.0f, 30.0f, cast(float[4])initButtonFill, cast(float[4])initButtonBorder, cast(float[4])initButtonText));
        actionRow.add(new UiButton("Secondary", 0.0f, 0.0f, 124.0f, 30.0f, cast(float[4])initButtonFill, cast(float[4])probeBorderB, cast(float[4])initButtonText));
        controlsBody.add(actionRow);

        auto controlsSection = new UiFrameBox(0.0f, 0.0f, 0.0f, 326.0f, [0.10f, 0.15f, 0.16f, 0.92f], [0.34f, 0.82f, 0.46f, 1.00f], 10.0f, 8.0f, 10.0f, 8.0f);
        controlsSection.setLayoutHint(0.0f, 326.0f, 0.0f, 326.0f, float.max, 326.0f, 1.0f, 0.0f);
        controlsSection.add(controlsBody);

        content.add(layoutSection);
        content.add(controlsSection);
        content.setLayoutHint(0.0f, 0.0f, 0.0f, 0.0f, float.max, float.max, 1.0f, 1.0f);

        UiLayoutContext layoutContext;
        content.layout(layoutContext);
        const minimumWidth = content.width + 34.0f;
        const minimumHeight = content.height + window.headerHeight + 30.0f;
        window.minimumWidth = minimumWidth;
        window.minimumHeight = minimumHeight;
        if (window.width < minimumWidth)
            window.width = minimumWidth;
        if (window.height < minimumHeight)
            window.height = minimumHeight;

        window.add(content);
        window.visible = true;
        window.onClose = onClose;
        window.onHeaderDragStart = onHeaderDragStart;
        window.onHeaderDragMove = onHeaderDragMove;
        window.onHeaderDragEnd = onHeaderDragEnd;
        window.onResizeStart = onResizeStart;
        window.onResizeMove = onResizeMove;
        window.onResizeEnd = onResizeEnd;
    }

    void layout(ref UiLayoutContext context)
    {
        window.layoutWindow(context);
    }
}

/** Builds a retained window chrome demo with runtime flag toggles. */
final class ChromeDemoWindow
{
    UiWindow window;
    UiVBox content;
    private UiLabel summaryLabel;
    private UiToggle sizeableToggle;
    private UiToggle closableToggle;
    private UiToggle dragableToggle;
    private UiToggle stackableToggle;
    private UiToggle headerToggle;
    private UiToggle titleToggle;
    private UiToggle borderToggle;

    this(uint serial)
    {
        const windowTitle = format("Chrome Demo #%u", serial);
        window = new UiWindow(windowTitle, 54.0f, 54.0f, 360.0f, 320.0f, [0.10f, 0.12f, 0.16f, 0.95f], [0.14f, 0.16f, 0.20f, 0.98f], [1.00f, 0.98f, 0.82f, 1.00f], true, true, true, 14.0f, 12.0f, 14.0f, 12.0f);

        content = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, contentSpacing);
        content.setLayoutHint(0.0f, 0.0f, 0.0f, 0.0f, float.max, float.max, 1.0f, 1.0f);
        summaryLabel = new UiLabel("", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpTextColor);
        sizeableToggle = new UiToggle("Resize grips", true, 0.0f, 0.0f, 220.0f, 28.0f);
        closableToggle = new UiToggle("Close button", true, 0.0f, 0.0f, 220.0f, 28.0f);
        dragableToggle = new UiToggle("Drag header", true, 0.0f, 0.0f, 220.0f, 28.0f);
        stackableToggle = new UiToggle("MMB stacking", true, 0.0f, 0.0f, 220.0f, 28.0f);
        headerToggle = new UiToggle("Header band", true, 0.0f, 0.0f, 220.0f, 28.0f);
        titleToggle = new UiToggle("Title text", true, 0.0f, 0.0f, 220.0f, 28.0f);
        borderToggle = new UiToggle("Outer border", true, 0.0f, 0.0f, 220.0f, 28.0f);

        sizeableToggle.onChanged = (value) { updateWindowChrome(); };
        closableToggle.onChanged = (value) { updateWindowChrome(); };
        dragableToggle.onChanged = (value) { updateWindowChrome(); };
        stackableToggle.onChanged = (value) { updateWindowChrome(); };
        headerToggle.onChanged = (value) { updateWindowChrome(); };
        titleToggle.onChanged = (value) { updateWindowChrome(); };
        borderToggle.onChanged = (value) { updateWindowChrome(); };

        content.add(summaryLabel);
        content.add(new UiSpacer(0.0f, sectionSpacing));
        content.add(sizeableToggle);
        content.add(closableToggle);
        content.add(dragableToggle);
        content.add(stackableToggle);
        content.add(headerToggle);
        content.add(titleToggle);
        content.add(borderToggle);
        window.add(content);
        window.visible = true;
        updateWindowChrome();
    }

    void updateWindowChrome()
    {
        window.setChromeFlags(sizeableToggle.checked, closableToggle.checked, dragableToggle.checked, stackableToggle.checked);
        window.setChromeVisibility(headerToggle.checked, titleToggle.checked, borderToggle.checked);
        summaryLabel.text = format("resize %s, close %s, header %s, border %s", sizeableToggle.checked ? "on" : "off", closableToggle.checked && headerToggle.checked ? "on" : "off", headerToggle.checked ? "on" : "off", borderToggle.checked ? "on" : "off");
    }
}

/** Builds a retained audio demo window that can be spawned repeatedly. */
final class AudioDemoWindow
{
    UiWindow window;
    UiVBox content;
    private UiLabel summaryLabel;
    private UiButton uiClickButton;
    private UiButton masterPreviewButton;
    private UiButton musicPreviewButton;
    private UiButton effectsPreviewButton;
    void delegate(DemoAudioPreviewKind) onAudioEvent;

    this(uint serial)
    {
        const windowTitle = format("Audio Demo #%u", serial);
        window = new UiWindow(windowTitle, 72.0f, 72.0f, 384.0f, 230.0f, [0.10f, 0.12f, 0.16f, 0.95f], [0.14f, 0.16f, 0.20f, 0.98f], [1.00f, 0.98f, 0.82f, 1.00f], true, true, true, 14.0f, 12.0f, 14.0f, 12.0f);

        content = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, contentSpacing);
        content.setLayoutHint(0.0f, 0.0f, 0.0f, 0.0f, float.max, float.max, 1.0f, 1.0f);
        summaryLabel = new UiLabel("Synthetic clips through AudioEvent path", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpTextColor);
        uiClickButton = buildButton("UI click", DemoAudioPreviewKind.ui);
        masterPreviewButton = buildButton("Master bus preview", DemoAudioPreviewKind.master);
        musicPreviewButton = buildButton("Music bus preview", DemoAudioPreviewKind.music);
        effectsPreviewButton = buildButton("Effects bus preview", DemoAudioPreviewKind.effects);

        auto rowA = new UiHBox(0.0f, 0.0f, 0.0f, 0.0f, contentSpacing);
        rowA.setLayoutHint(0.0f, 32.0f, 0.0f, 32.0f, float.max, 32.0f, 1.0f, 0.0f);
        rowA.add(uiClickButton);
        rowA.add(masterPreviewButton);

        auto rowB = new UiHBox(0.0f, 0.0f, 0.0f, 0.0f, contentSpacing);
        rowB.setLayoutHint(0.0f, 32.0f, 0.0f, 32.0f, float.max, 32.0f, 1.0f, 0.0f);
        rowB.add(musicPreviewButton);
        rowB.add(effectsPreviewButton);

        content.add(summaryLabel);
        content.add(new UiSpacer(0.0f, sectionSpacing));
        content.add(rowA);
        content.add(rowB);
        window.add(content);
        window.visible = true;
    }

    private UiButton buildButton(string caption, DemoAudioPreviewKind kind)
    {
        auto button = new UiButton(caption, 0.0f, 0.0f, 156.0f, 30.0f, cast(float[4])initButtonFill, cast(float[4])initButtonBorder, cast(float[4])initButtonText, UiTextStyle.small);
        button.onClick = ()
        {
            if (onAudioEvent !is null)
                onAudioEvent(kind);
        };
        return button;
    }
}

/** Builds a retained input and focus demo window that can be spawned repeatedly. */
final class InputDemoWindow
{
    UiWindow window;
    UiVBox content;
    private UiLabel summaryLabel;
    private UiTextField nameField;
    private UiToggle captureToggle;
    private UiSlider speedSlider;
    private UiDropdown modeDropdown;
    private UiButton applyButton;
    private UiButton clearButton;
    private uint applyCount;

    this(uint serial, void delegate(UiDropdown, float, float, float, float) onDropdownOpen)
    {
        const windowTitle = format("Input Demo #%u", serial);
        window = new UiWindow(windowTitle, 90.0f, 90.0f, 420.0f, 286.0f, [0.10f, 0.12f, 0.16f, 0.95f], [0.14f, 0.16f, 0.20f, 0.98f], [1.00f, 0.98f, 0.82f, 1.00f], true, true, true, 14.0f, 12.0f, 14.0f, 12.0f);

        content = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, contentSpacing);
        content.setLayoutHint(0.0f, 0.0f, 0.0f, 0.0f, float.max, float.max, 1.0f, 1.0f);
        summaryLabel = new UiLabel("", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpTextColor);
        nameField = new UiTextField("focus", "type here", 0.0f, 0.0f, 180.0f, 28.0f);
        captureToggle = new UiToggle("Keyboard mode", false, 0.0f, 0.0f, 156.0f, 28.0f);
        speedSlider = new UiSlider("Repeat", 0.0f, 1.0f, 0.35f, 0.0f, 0.0f, 180.0f, 32.0f);
        modeDropdown = new UiDropdown("Route", ["Local", "Modal", "Global"], 0, 0.0f, 0.0f, 160.0f, 28.0f);
        modeDropdown.onOpenRequested = onDropdownOpen;
        applyButton = new UiButton("Apply", 0.0f, 0.0f, 104.0f, 30.0f, cast(float[4])initButtonFill, cast(float[4])initButtonBorder, cast(float[4])initButtonText);
        clearButton = new UiButton("Clear", 0.0f, 0.0f, 104.0f, 30.0f, cast(float[4])initButtonFill, cast(float[4])probeBorderC, cast(float[4])initButtonText);

        nameField.onChanged = (value) { updateSummary(); };
        captureToggle.onChanged = (value) { updateSummary(); };
        speedSlider.onChanged = (value) { updateSummary(); };
        modeDropdown.onChanged = (index, value) { updateSummary(); };
        applyButton.onClick = ()
        {
            ++applyCount;
            updateSummary();
        };
        clearButton.onClick = ()
        {
            nameField.setText("");
            captureToggle.checked = false;
            speedSlider.setValue(0.0f);
            modeDropdown.selectIndex(0);
            updateSummary();
        };

        auto rowA = new UiHBox(0.0f, 0.0f, 0.0f, 0.0f, contentSpacing);
        rowA.setLayoutHint(0.0f, 32.0f, 0.0f, 32.0f, float.max, 32.0f, 1.0f, 0.0f);
        rowA.add(nameField);
        rowA.add(captureToggle);

        auto rowB = new UiHBox(0.0f, 0.0f, 0.0f, 0.0f, contentSpacing);
        rowB.setLayoutHint(0.0f, 34.0f, 0.0f, 34.0f, float.max, 34.0f, 1.0f, 0.0f);
        rowB.add(speedSlider);
        rowB.add(modeDropdown);

        auto rowC = new UiHBox(0.0f, 0.0f, 0.0f, 0.0f, contentSpacing);
        rowC.setLayoutHint(0.0f, 32.0f, 0.0f, 32.0f, float.max, 32.0f, 1.0f, 0.0f);
        rowC.add(applyButton);
        rowC.add(clearButton);

        content.add(summaryLabel);
        content.add(new UiSpacer(0.0f, sectionSpacing));
        content.add(rowA);
        content.add(rowB);
        content.add(rowC);
        window.add(content);
        window.visible = true;
        updateSummary();
    }

    private void updateSummary()
    {
        summaryLabel.text = format("focus text='%s', mode=%s, repeat=%.2f, apply=%u", nameField.text, modeDropdown.selectedText(), speedSlider.value, applyCount);
    }
}

/** Builds a retained selection and popup demo window that can be spawned repeatedly. */
final class SelectionDemoWindow
{
    UiWindow window;
    UiVBox content;
    private UiLabel summaryLabel;
    private UiDropdown popupDropdown;
    private UiListBox listBox;
    private UiButton edgePopupButton;

    this(uint serial, void delegate(UiDropdown, float, float, float, float) onDropdownOpen)
    {
        const windowTitle = format("Selection Demo #%u", serial);
        window = new UiWindow(windowTitle, 108.0f, 108.0f, 430.0f, 278.0f, [0.10f, 0.12f, 0.16f, 0.95f], [0.14f, 0.16f, 0.20f, 0.98f], [1.00f, 0.98f, 0.82f, 1.00f], true, true, true, 14.0f, 12.0f, 14.0f, 12.0f);

        content = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, contentSpacing);
        content.setLayoutHint(0.0f, 0.0f, 0.0f, 0.0f, float.max, float.max, 1.0f, 1.0f);
        summaryLabel = new UiLabel("", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpTextColor);
        popupDropdown = new UiDropdown("Popup", ["North", "East", "South", "West"], 0, 0.0f, 0.0f, 170.0f, 28.0f);
        popupDropdown.onOpenRequested = onDropdownOpen;
        listBox = new UiListBox(["Alpha", "Beta", "Gamma", "Delta"], 0, 0.0f, 0.0f, 170.0f, 96.0f, UiTextStyle.medium, 24.0f);
        edgePopupButton = new UiButton("Edge popup", 0.0f, 0.0f, 130.0f, 30.0f, cast(float[4])initButtonFill, cast(float[4])probeBorderB, cast(float[4])initButtonText);

        popupDropdown.onChanged = (index, value) { updateSummary(); };
        listBox.onChanged = (index, value) { updateSummary(); };
        listBox.onActivated = (index, value) { updateSummary(); };
        edgePopupButton.onClick = ()
        {
            if (onDropdownOpen !is null)
                onDropdownOpen(popupDropdown, window.x + window.width - 18.0f, window.y + window.height - 18.0f, 18.0f, 18.0f);
        };

        auto rowA = new UiHBox(0.0f, 0.0f, 0.0f, 0.0f, contentSpacing);
        rowA.setLayoutHint(0.0f, 32.0f, 0.0f, 32.0f, float.max, 32.0f, 1.0f, 0.0f);
        rowA.add(popupDropdown);
        rowA.add(edgePopupButton);

        auto rowB = new UiHBox(0.0f, 0.0f, 0.0f, 0.0f, contentSpacing);
        rowB.setLayoutHint(0.0f, 100.0f, 0.0f, 100.0f, float.max, 100.0f, 1.0f, 0.0f);
        rowB.add(listBox);
        rowB.add(new UiLabel("Use arrows/Enter or mouse; outside click dismisses popups.", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpTextColor));

        content.add(summaryLabel);
        content.add(new UiSpacer(0.0f, sectionSpacing));
        content.add(rowA);
        content.add(rowB);
        window.add(content);
        window.visible = true;
        updateSummary();
    }

    private void updateSummary()
    {
        summaryLabel.text = format("dropdown=%s, list=%s", popupDropdown.selectedText(), listBox.selectedText());
    }
}

/** Creates a new retained layout demo window. */
LayoutDemoWindow buildLayoutDemoWindow(uint serial, void delegate() onClose = null, void delegate(float, float) onHeaderDragStart = null, void delegate(float, float) onHeaderDragMove = null, void delegate() onHeaderDragEnd = null, void delegate(UiResizeHandle) onResizeStart = null, void delegate(UiResizeHandle, float, float) onResizeMove = null, void delegate(UiResizeHandle) onResizeEnd = null)
{
    return new LayoutDemoWindow(serial, onClose, onHeaderDragStart, onHeaderDragMove, onHeaderDragEnd, onResizeStart, onResizeMove, onResizeEnd);
}

/** Creates a new retained layout demo window with dropdown popup integration. */
LayoutDemoWindow buildLayoutDemoWindow(uint serial, void delegate(UiDropdown, float, float, float, float) onDropdownOpen, void delegate() onClose = null, void delegate(float, float) onHeaderDragStart = null, void delegate(float, float) onHeaderDragMove = null, void delegate() onHeaderDragEnd = null, void delegate(UiResizeHandle) onResizeStart = null, void delegate(UiResizeHandle, float, float) onResizeMove = null, void delegate(UiResizeHandle) onResizeEnd = null)
{
    return new LayoutDemoWindow(serial, onDropdownOpen, onClose, onHeaderDragStart, onHeaderDragMove, onHeaderDragEnd, onResizeStart, onResizeMove, onResizeEnd);
}


private enum float windowMargin = 10.0f;
private enum float sidebarCollapsedWidth = 44.0f;
private enum float sidebarExpandedWidth = 124.0f;
private enum float sidebarButtonSize = 32.0f;
private enum float sidebarPadding = 5.0f;
private enum float sidebarSpacing = 4.0f;
private enum float sidebarFallbackHeight = 260.0f;
private enum float helpWidth = 462.0f;
private enum float helpHeight = 252.0f;
private enum float statusWidth = 348.0f;
private enum float statusHeight = 144.0f;
private enum float settingsWidth = 372.0f;
private enum float settingsHeight = 282.0f;
private enum float settingsPageHeight = 138.0f;
private enum float dropdownPopupRowHeight = 28.0f;
private enum float testWindowWidth = 560.0f;
private enum float testWindowHeight = 440.0f;
private enum float contentSpacing = 6.0f;
private enum float sectionSpacing = 8.0f;
private enum float probeSpacing = 10.0f;
private enum float probeMargin = 12.0f;
private enum float windowContentPaddingX = 17.0f;
private enum float windowContentPaddingY = 15.0f;
private enum float overlayWindowDepth = 0.10f;

private immutable float[4] initButtonFill = [0.16f, 0.18f, 0.24f, 0.96f];
private immutable float[4] initButtonBorder = [0.20f, 0.56f, 0.98f, 1.00f];
private immutable float[4] initButtonText = [1.00f, 1.00f, 1.00f, 1.00f];
private immutable float[4] sidebarBodyColor = [0.08f, 0.09f, 0.11f, 0.96f];
private immutable float[4] sidebarButtonFill = [0.15f, 0.17f, 0.21f, 0.98f];
private immutable float[4] sidebarButtonBorder = [0.24f, 0.58f, 0.80f, 1.00f];
private immutable float[4] sidebarButtonText = [1.00f, 1.00f, 1.00f, 1.00f];

private immutable float[4] helpBodyColor = [0.10f, 0.12f, 0.16f, 0.95f];
private immutable float[4] helpHeaderColor = [0.14f, 0.16f, 0.20f, 0.98f];
private immutable float[4] helpTitleColor = [1.00f, 0.98f, 0.82f, 1.00f];
private immutable float[4] helpAccentColor = [0.72f, 0.96f, 1.00f, 1.00f];
private immutable float[4] helpTextColor = [1.00f, 1.00f, 1.00f, 1.00f];

private immutable float[4] statusBodyColor = [0.10f, 0.12f, 0.16f, 0.95f];
private immutable float[4] statusHeaderColor = [0.14f, 0.16f, 0.20f, 0.98f];
private immutable float[4] statusTitleColor = [1.00f, 0.98f, 0.82f, 1.00f];
private immutable float[4] statusAccentColor = [0.72f, 0.96f, 1.00f, 1.00f];
private immutable float[4] statusTextColor = [1.00f, 1.00f, 1.00f, 1.00f];

private immutable float[4] settingsBodyColor = [0.10f, 0.12f, 0.16f, 0.95f];
private immutable float[4] settingsHeaderColor = [0.14f, 0.16f, 0.20f, 0.98f];
private immutable float[4] settingsTitleColor = [1.00f, 0.98f, 0.82f, 1.00f];
private immutable float[4] settingsAccentColor = [0.86f, 0.96f, 1.00f, 1.00f];
private immutable float[4] settingsTextColor = [1.00f, 1.00f, 1.00f, 1.00f];

private immutable float[4] probeFillA = [0.17f, 0.20f, 0.28f, 0.96f];
private immutable float[4] probeFillB = [0.14f, 0.24f, 0.20f, 0.96f];
private immutable float[4] probeFillC = [0.24f, 0.16f, 0.20f, 0.96f];
private immutable float[4] probeFillD = [0.18f, 0.18f, 0.18f, 0.96f];
private immutable float[4] probeBorderA = [0.20f, 0.56f, 0.98f, 1.00f];
private immutable float[4] probeBorderB = [0.34f, 0.82f, 0.46f, 1.00f];
private immutable float[4] probeBorderC = [0.92f, 0.46f, 0.46f, 1.00f];
private immutable float[4] probeBorderD = [0.82f, 0.72f, 0.28f, 1.00f];

final class DemoUiScreen : UiScreen
{
    DemoSettings settingsDraft;
    bool sceneMouseDragging;
    void delegate() onApplySettings;
    void delegate() onSaveSettings;
    void delegate(DemoAudioPreviewKind) onPreviewAudioSettings;

    private UiWindow sidebarWindow;
    private UiWindow helpWindow;
    private UiWindow statusWindow;
    private UiWindow settingsWindow;
    private LayoutDemoWindow[] testWindows;
    private ChromeDemoWindow[] chromeWindows;
    private InputDemoWindow[] inputWindows;
    private SelectionDemoWindow[] selectionWindows;
    private UiVBox sidebarContent;
    private UiVBox helpContent;
    private UiVBox statusContent;
    private UiVBox settingsContent;
    private UiVBox settingsBody;
    private UiHBox settingsActionRow;
    private UiButton sidebarExpandButton;
    private UiButton sidebarHelpButton;
    private UiButton sidebarStatusButton;
    private UiButton sidebarSettingsButton;
    private UiButton sidebarWidgetButton;
    private UiButton sidebarChromeButton;
    private UiButton sidebarInputButton;
    private UiButton sidebarSelectionButton;
    private UiButton sidebarAudioButton;
    private UiButton sidebarCloseAllButton;
    private UiButton sidebarExitButton;
    private UiWindow dropdownPopupWindow;

    private UiLabel helpTitleLabel;
    private UiLabel helpIntroLabel;
    private UiLabel helpLayoutLabel;
    private UiLabel helpCloseLabel;
    private UiLabel helpShapeLabel;
    private UiLabel helpFocusLabel;
    private UiLabel helpDebugLegendTitleLabel;
    private UiLabel helpDebugLegendWindowLabel;
    private UiLabel helpDebugLegendSurfaceLabel;
    private UiLabel helpDebugLegendVBoxLabel;
    private UiLabel helpDebugLegendHBoxLabel;
    private UiLabel helpDebugLegendGridLabel;
    private UiLabel helpDebugLegendSpacerLabel;
    private UiLabel helpDebugLegendWidgetLabel;

    private UiLabel statusBuildLabel;
    private UiLabel statusFpsLabel;
    private UiLabel statusSceneLabel;
    private UiLabel statusModeLabel;
    private UiLabel statusRotationLabel;
    private UiLabel statusViewportLabel;

    private UiLabel settingsTitleLabel;
    private UiLabel settingsIntroLabel;
    private UiLabel settingsProfileLabel;
    private UiTabBar settingsTabBar;
    private UiContentBox settingsPageBox;
    private UiVBox settingsDisplayPage;
    private UiVBox settingsUiPage;
    private UiVBox settingsAudioPage;
    private UiDropdown settingsWindowModeDropdown;
    private UiTextField settingsWidthField;
    private UiTextField settingsHeightField;
    private UiToggle settingsVsyncToggle;
    private UiSlider settingsScaleSlider;
    private UiDropdown settingsThemeDropdown;
    private UiToggle settingsCompactToggle;
    private UiSlider settingsMasterVolumeSlider;
    private UiSlider settingsMusicVolumeSlider;
    private UiSlider settingsEffectsVolumeSlider;
    private UiButton settingsApplyButton;
    private UiButton settingsSaveButton;

    private bool helpAnchored;
    private bool statusAnchored;
    private bool settingsAnchored;
    private bool sidebarExpanded;

    private uint nextTestWindowSerial = 1;
    private uint nextChromeWindowSerial = 1;
    private uint nextInputWindowSerial = 1;
    private uint nextSelectionWindowSerial = 1;
    private uint nextAudioWindowSerial = 1;
    private AudioDemoWindow[] audioWindows;

    bool quitRequested;

    override void onInitialize()
    {
        settingsDraft = DemoSettings.init;
        sceneMouseDragging = false;
        sidebarExpanded = false;
        testWindows = [];
        chromeWindows = [];
        inputWindows = [];
        selectionWindows = [];

        buildSidebarWindow();
        buildHelpWindow();
        buildStatusWindow();
        buildSettingsWindow();
        addWindow(sidebarWindow);
        autoSizeWindow(helpWindow, helpContent, windowContentPaddingX, windowContentPaddingY, windowContentPaddingX, windowContentPaddingY, helpWidth, helpHeight);
        autoSizeWindow(statusWindow, statusContent, windowContentPaddingX, windowContentPaddingY, windowContentPaddingX, windowContentPaddingY, statusWidth, statusHeight);
        autoSizeWindow(settingsWindow, settingsContent, windowContentPaddingX, windowContentPaddingY, windowContentPaddingX, windowContentPaddingY, settingsWidth, settingsHeight);
        updateWindowState();
    }

    void syncViewport(float extentWidth, float extentHeight, float fps, string currentShapeName, string currentRenderModeName, string buildVersion, float yawDegrees = 0.0f, float pitchDegrees = 0.0f)
    {
        super.syncViewport(extentWidth, extentHeight);
        updateStatusText(fps, currentShapeName, currentRenderModeName, buildVersion, yawDegrees, pitchDegrees);
        ensureWindowLayout();
    }

    UiOverlayGeometry buildOverlayVertices(float extentWidth, float extentHeight, float fps, string currentShapeName, string currentRenderModeName, string buildVersion, float yawDegrees = 0.0f, float pitchDegrees = 0.0f, bool debugWidgetBounds = false)
    {
        syncViewport(extentWidth, extentHeight, fps, currentShapeName, currentRenderModeName, buildVersion, yawDegrees, pitchDegrees);
        return buildOverlayGeometry(debugWidgetBounds, overlayWindowDepth);
    }

    void toggleHelpWindow()
    {
        toggleSingletonWindow(helpWindow);
    }

    void showHelpWindow()
    {
        showSingletonWindow(helpWindow);
    }

    void toggleStatusWindow()
    {
        toggleSingletonWindow(statusWindow);
    }

    void showStatusWindow()
    {
        showSingletonWindow(statusWindow);
    }

    void toggleSettingsWindow()
    {
        toggleSingletonWindow(settingsWindow);
    }

    void toggleSingletonWindow(UiWindow window)
    {
        toggleWindow(window);
        if (sidebarWindow !is null)
            bringWindowToFront(sidebarWindow);
    }

    void showSettingsDialog(const(DemoSettings)* liveSettings)
    {
        if (liveSettings !is null)
            settingsDraft = *liveSettings;
        refreshSettingsControls();
        showSingletonWindow(settingsWindow);
    }

    void showSingletonWindow(UiWindow window)
    {
        if (window is null)
            return;

        showWindow(window);
        if (sidebarWindow !is null)
            bringWindowToFront(sidebarWindow);
    }

    void requestQuit()
    {
        quitRequested = true;
    }

    void openSettingsDialog(const(DemoSettings)* liveSettings)
    {
        showSettingsDialog(liveSettings);
    }

    void toggleSettingsDialog(const(DemoSettings)* liveSettings)
    {
        if (liveSettings !is null)
            settingsDraft = *liveSettings;
        refreshSettingsControls();
        toggleSingletonWindow(settingsWindow);
    }

    void setSettingsDraft(const(DemoSettings)* liveSettings)
    {
        if (liveSettings is null)
            return;

        settingsDraft = *liveSettings;
        refreshSettingsControls();
    }

    void updateWindowState()
    {
        hideWindow(helpWindow, false);
        hideWindow(statusWindow, false);
        hideWindow(settingsWindow, false);
    }

    void buildSidebarWindow()
    {
        sidebarWindow = new UiWindow("Demo Sidebar", 0.0f, 0.0f, currentSidebarWidth(), sidebarFallbackHeight, cast(float[4])sidebarBodyColor, cast(float[4])sidebarBodyColor, cast(float[4])sidebarButtonText, false, false, false, 0.0f, 0.0f, 0.0f, 0.0f);
        sidebarWindow.setChromeFlags(false, false, false, false);
        sidebarWindow.setChromeVisibility(false, false, false);
        sidebarWindow.minimumWidth = sidebarCollapsedWidth;
        sidebarWindow.minimumHeight = sidebarFallbackHeight;

        sidebarContent = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, sidebarSpacing, sidebarPadding, sidebarPadding, sidebarPadding, sidebarPadding);
        sidebarContent.setLayoutHint(currentSidebarWidth(), sidebarFallbackHeight, currentSidebarWidth(), sidebarFallbackHeight, currentSidebarWidth(), float.max, 0.0f, 1.0f);
        sidebarExpandButton = buildSidebarButton(">>", &toggleSidebarExpanded);
        sidebarHelpButton = buildSidebarButton("?", &toggleHelpWindow);
        sidebarStatusButton = buildSidebarButton("S", &toggleStatusWindow);
        sidebarSettingsButton = buildSidebarButton("Cfg", () { toggleSettingsDialog(null); });
        sidebarWidgetButton = buildSidebarButton("W", &spawnLayoutTestWindow);
        sidebarChromeButton = buildSidebarButton("C", &spawnChromeDemoWindow);
        sidebarInputButton = buildSidebarButton("I", &spawnInputDemoWindow);
        sidebarSelectionButton = buildSidebarButton("Sel", &spawnSelectionDemoWindow);
        sidebarAudioButton = buildSidebarButton("A", &spawnAudioDemoWindow);
        sidebarCloseAllButton = buildSidebarButton("All", &closeAllDemoWindows);
        sidebarExitButton = buildSidebarButton("X", &requestQuit);
        auto sidebarBottomSpacer = new UiSpacer(0.0f, 0.0f);
        sidebarBottomSpacer.setLayoutHint(0.0f, 0.0f, 0.0f, 0.0f, float.max, float.max, 0.0f, 1.0f);

        sidebarContent.add(sidebarExpandButton);
        sidebarContent.add(new UiSpacer(0.0f, sidebarSpacing));
        sidebarContent.add(sidebarWidgetButton);
        sidebarContent.add(sidebarChromeButton);
        sidebarContent.add(sidebarInputButton);
        sidebarContent.add(sidebarSelectionButton);
        sidebarContent.add(sidebarAudioButton);
        sidebarContent.add(sidebarBottomSpacer);
        sidebarContent.add(sidebarHelpButton);
        sidebarContent.add(sidebarStatusButton);
        sidebarContent.add(sidebarSettingsButton);
        sidebarContent.add(sidebarCloseAllButton);
        sidebarContent.add(sidebarExitButton);
        sidebarWindow.add(sidebarContent);
        sidebarWindow.visible = true;
        refreshSidebarLabels();
    }

    UiButton buildSidebarButton(string caption, void delegate() onClick)
    {
        auto button = new UiButton(caption, 0.0f, 0.0f, sidebarButtonSize, sidebarButtonSize, cast(float[4])sidebarButtonFill, cast(float[4])sidebarButtonBorder, cast(float[4])sidebarButtonText, UiTextStyle.small, 2.0f, 0.5f);
        button.setLayoutHint(sidebarButtonSize, sidebarButtonSize, sidebarButtonSize, sidebarButtonSize, float.max, sidebarButtonSize, 1.0f, 0.0f);
        button.onClick = onClick;
        return button;
    }

    float currentSidebarWidth() const
    {
        return sidebarExpanded ? sidebarExpandedWidth : sidebarCollapsedWidth;
    }

    float sidebarReservedLeft() const
    {
        return currentSidebarWidth() + windowMargin;
    }

    void toggleSidebarExpanded()
    {
        sidebarExpanded = !sidebarExpanded;
        refreshSidebarLabels();
        helpAnchored = false;
        statusAnchored = false;
        settingsAnchored = false;
        ensureWindowLayout();
    }

    void refreshSidebarLabels()
    {
        const width = currentSidebarWidth();
        sidebarWindow.width = width;
        sidebarWindow.minimumWidth = width;
        sidebarContent.setLayoutHint(width, sidebarFallbackHeight, width, sidebarFallbackHeight, width, float.max, 0.0f, 1.0f);
        sidebarExpandButton.setCaption(sidebarExpanded ? "<<" : ">>");
        sidebarHelpButton.setCaption(sidebarExpanded ? "?  Help Desk" : "?");
        sidebarStatusButton.setCaption(sidebarExpanded ? "S  Status" : "S");
        sidebarSettingsButton.setCaption(sidebarExpanded ? "Cfg Settings" : "Cfg");
        sidebarWidgetButton.setCaption(sidebarExpanded ? "W  Widgets" : "W");
        sidebarChromeButton.setCaption(sidebarExpanded ? "C  Chrome" : "C");
        sidebarInputButton.setCaption(sidebarExpanded ? "I  Input" : "I");
        sidebarSelectionButton.setCaption(sidebarExpanded ? "Sel Select" : "Sel");
        sidebarAudioButton.setCaption(sidebarExpanded ? "A  Audio" : "A");
        sidebarCloseAllButton.setCaption(sidebarExpanded ? "All Close" : "All");
        sidebarExitButton.setCaption(sidebarExpanded ? "X  Exit" : "X");
        applySidebarButtonLayout(sidebarExpandButton);
        applySidebarButtonLayout(sidebarHelpButton);
        applySidebarButtonLayout(sidebarStatusButton);
        applySidebarButtonLayout(sidebarSettingsButton);
        applySidebarButtonLayout(sidebarWidgetButton);
        applySidebarButtonLayout(sidebarChromeButton);
        applySidebarButtonLayout(sidebarInputButton);
        applySidebarButtonLayout(sidebarSelectionButton);
        applySidebarButtonLayout(sidebarAudioButton);
        applySidebarButtonLayout(sidebarCloseAllButton);
        applySidebarButtonLayout(sidebarExitButton);
    }

    void applySidebarButtonLayout(UiButton button)
    {
        button.setLayoutHint(sidebarButtonSize, sidebarButtonSize, sidebarButtonSize, sidebarButtonSize, float.max, sidebarButtonSize, 1.0f, 0.0f);
    }

    void buildHelpWindow()
    {
        helpWindow = new UiWindow("Help Desk", sidebarReservedLeft(), windowMargin, helpWidth, helpHeight, cast(float[4])helpBodyColor, cast(float[4])helpHeaderColor, cast(float[4])helpTitleColor, true, true, true, 14.0f, 12.0f, 14.0f, 12.0f);

        helpContent = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, contentSpacing);
        helpTitleLabel = new UiLabel("Keyboard and mouse controls", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpAccentColor);
        helpIntroLabel = new UiLabel("Open windows: 0", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpTextColor);
        helpLayoutLabel = new UiLabel("Arrow keys rotate model; Shift accelerates; mouse drag rotates outside UI.", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpTextColor);
        helpShapeLabel = new UiLabel("+/- switch 3D model; F/T/W/H switch render modes.", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpTextColor);
        helpFocusLabel = new UiLabel("Tab/Shift+Tab move focus; Enter activates controls; D toggles UI bounds.", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpTextColor);
        helpCloseLabel = new UiLabel("Esc dismisses UI focus/popups/modals first; otherwise it quits.", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpTextColor);
        helpDebugLegendTitleLabel = new UiLabel("Debug bounds colors:", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpAccentColor);
        helpDebugLegendWindowLabel = new UiLabel("Orange: UiWindow", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpTextColor);
        helpDebugLegendSurfaceLabel = new UiLabel("Cyan: UiContentBox / UiFrameBox", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpTextColor);
        helpDebugLegendVBoxLabel = new UiLabel("Green: UiVBox", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpTextColor);
        helpDebugLegendHBoxLabel = new UiLabel("Blue: UiHBox", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpTextColor);
        helpDebugLegendGridLabel = new UiLabel("Purple: UiGrid", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpTextColor);
        helpDebugLegendSpacerLabel = new UiLabel("Yellow: UiSpacer", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpTextColor);
        helpDebugLegendWidgetLabel = new UiLabel("Red: basic widgets and controls", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])helpTextColor);

        helpContent.add(helpTitleLabel);
        helpContent.add(helpIntroLabel);
        helpContent.add(helpLayoutLabel);
        helpContent.add(helpShapeLabel);
        helpContent.add(helpFocusLabel);
        helpContent.add(helpCloseLabel);
        helpContent.add(new UiSpacer(0.0f, sectionSpacing));
        helpContent.add(helpDebugLegendTitleLabel);
        helpContent.add(helpDebugLegendWindowLabel);
        helpContent.add(helpDebugLegendSurfaceLabel);
        helpContent.add(helpDebugLegendVBoxLabel);
        helpContent.add(helpDebugLegendHBoxLabel);
        helpContent.add(helpDebugLegendGridLabel);
        helpContent.add(helpDebugLegendSpacerLabel);
        helpContent.add(helpDebugLegendWidgetLabel);
        helpWindow.add(helpContent);
        helpWindow.visible = false;
        helpWindow.onClose = ()
        {
            hideWindow(helpWindow);
            logLine("UiWindow close: Help Desk");
        };
        registerWindowInteractionHandlers(helpWindow);
        addWindow(helpWindow);
    }

    void buildStatusWindow()
    {
        statusWindow = new UiWindow("Status", windowMargin, windowMargin, statusWidth, statusHeight, cast(float[4])statusBodyColor, cast(float[4])statusHeaderColor, cast(float[4])statusTitleColor, false, false, false, 10.0f, 10.0f, 10.0f, 10.0f);
        statusWindow.setChromeFlags(false, false, false, true);
        statusWindow.setChromeVisibility(false, false, false);
        statusWindow.setBackfillVisible(false);
        statusWindow.setPinnedEdges(false, true, true, false);
        statusWindow.setPinMargins(0.0f, windowMargin, 0.0f, 0.0f);

        statusContent = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, contentSpacing);
        statusBuildLabel = new UiLabel("Build: pending", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])statusTextColor);
        statusFpsLabel = new UiLabel("FPS: pending", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])statusTextColor);
        statusSceneLabel = new UiLabel("Szene: pending", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])statusTextColor);
        statusModeLabel = new UiLabel("Modus: pending", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])statusTextColor);
        statusRotationLabel = new UiLabel("Rotation: pending", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])statusTextColor);
        statusViewportLabel = new UiLabel("Viewport: pending", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])statusAccentColor);

        statusContent.add(statusBuildLabel);
        statusContent.add(statusFpsLabel);
        statusContent.add(statusSceneLabel);
        statusContent.add(statusModeLabel);
        statusContent.add(statusRotationLabel);
        statusContent.add(statusViewportLabel);
        statusWindow.add(statusContent);
        statusWindow.visible = false;
        statusWindow.onClose = ()
        {
            hideWindow(statusWindow);
            logLine("UiWindow close: Status");
        };
        registerWindowInteractionHandlers(statusWindow);
        addWindow(statusWindow);
    }

    void buildSettingsWindow()
    {
        settingsWindow = new UiWindow("Settings", windowMargin, windowMargin, settingsWidth, settingsHeight, cast(float[4])settingsBodyColor, cast(float[4])settingsHeaderColor, cast(float[4])settingsTitleColor, true, true, true, 14.0f, 12.0f, 14.0f, 12.0f);

        settingsContent = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, contentSpacing);
        settingsTitleLabel = new UiLabel("Runtime configuration", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])settingsAccentColor);
        settingsIntroLabel = new UiLabel("Apply changes this run. Save writes the config file.", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])settingsTextColor);
        settingsProfileLabel = new UiLabel("Profile: default", 0.0f, 0.0f, UiTextStyle.medium, cast(float[4])settingsTextColor);
        settingsTabBar = new UiTabBar(["Display", "UI", "Audio"], 0, 0.0f, 0.0f, 300.0f, 28.0f);
        settingsWindowModeDropdown = new UiDropdown("Window Mode", ["windowed", "fullscreen", "borderless"], 0, 0.0f, 0.0f, 220.0f, 28.0f);
        settingsWidthField = new UiTextField("", "Width", 0.0f, 0.0f, 104.0f, 28.0f);
        settingsHeightField = new UiTextField("", "Height", 0.0f, 0.0f, 104.0f, 28.0f);
        settingsVsyncToggle = new UiToggle("VSync", false, 0.0f, 0.0f, 220.0f, 28.0f);
        settingsScaleSlider = new UiSlider("UI Scale", 0.50f, 2.00f, 1.00f, 0.0f, 0.0f, 220.0f, 32.0f);
        settingsThemeDropdown = new UiDropdown("Theme", ["midnight", "classic", "contrast"], 0, 0.0f, 0.0f, 220.0f, 28.0f);
        settingsCompactToggle = new UiToggle("Compact Windows", false, 0.0f, 0.0f, 220.0f, 28.0f);
        settingsMasterVolumeSlider = new UiSlider("Master", 0.0f, 1.0f, 1.0f, 0.0f, 0.0f, 220.0f, 32.0f);
        settingsMusicVolumeSlider = new UiSlider("Music", 0.0f, 1.0f, 0.8f, 0.0f, 0.0f, 220.0f, 32.0f);
        settingsEffectsVolumeSlider = new UiSlider("Effects", 0.0f, 1.0f, 0.8f, 0.0f, 0.0f, 220.0f, 32.0f);
        settingsApplyButton = new UiButton("Apply", 0.0f, 0.0f, 104.0f, 30.0f, cast(float[4])initButtonFill, cast(float[4])initButtonBorder, cast(float[4])initButtonText);
        settingsSaveButton = new UiButton("Save", 0.0f, 0.0f, 104.0f, 30.0f, cast(float[4])initButtonFill, cast(float[4])initButtonBorder, cast(float[4])initButtonText);

        settingsTabBar.onChanged = (index, value) { updateSettingsPageVisibility(); };
        settingsWindowModeDropdown.onChanged = (index, value) { settingsDraft.display.windowMode = value; updateSettingsSummary(); };
        settingsWindowModeDropdown.onOpenRequested = &openDropdownPopup;
        settingsWidthField.onChanged = (value) { settingsDraft.display.windowWidth = parseUintSetting(value, settingsDraft.display.windowWidth); updateSettingsSummary(); };
        settingsHeightField.onChanged = (value) { settingsDraft.display.windowHeight = parseUintSetting(value, settingsDraft.display.windowHeight); updateSettingsSummary(); };
        settingsVsyncToggle.onChanged = (value) { settingsDraft.display.vsync = value; updateSettingsSummary(); };
        settingsScaleSlider.onChanged = (value) { settingsDraft.display.scale = value; updateSettingsSummary(); };
        settingsThemeDropdown.onChanged = (index, value) { settingsDraft.ui.theme = value; updateSettingsSummary(); };
        settingsThemeDropdown.onOpenRequested = &openDropdownPopup;
        settingsCompactToggle.onChanged = (value) { settingsDraft.ui.compactWindows = value; updateSettingsSummary(); };
        settingsMasterVolumeSlider.onChanged = (value) { settingsDraft.audio.masterVolume = value; updateSettingsSummary(); };
        settingsMusicVolumeSlider.onChanged = (value) { settingsDraft.audio.musicVolume = value; updateSettingsSummary(); };
        settingsEffectsVolumeSlider.onChanged = (value) { settingsDraft.audio.effectsVolume = value; updateSettingsSummary(); };
        settingsMasterVolumeSlider.onCommitted = (value) { previewAudioSettingsFromDialog(DemoAudioPreviewKind.master); };
        settingsMusicVolumeSlider.onCommitted = (value) { previewAudioSettingsFromDialog(DemoAudioPreviewKind.music); };
        settingsEffectsVolumeSlider.onCommitted = (value) { previewAudioSettingsFromDialog(DemoAudioPreviewKind.effects); };
        settingsApplyButton.onClick = &applySettingsFromDialog;
        settingsSaveButton.onClick = &saveSettingsFromDialog;

        auto sizeRow = new UiHBox(0.0f, 0.0f, 0.0f, 0.0f, contentSpacing);
        sizeRow.add(settingsWidthField);
        sizeRow.add(settingsHeightField);

        settingsBody = new UiVBox(0.0f, 0.0f, 0.0f, 0.0f, contentSpacing);
        settingsBody.setLayoutHint(0.0f, 0.0f, 0.0f, 0.0f, float.max, float.max, 1.0f, 1.0f);
        settingsDisplayPage = new UiVBox(0.0f, 0.0f, 0.0f, settingsPageHeight, contentSpacing);
        settingsDisplayPage.setLayoutHint(0.0f, settingsPageHeight, 0.0f, settingsPageHeight, float.max, settingsPageHeight, 1.0f, 0.0f);
        settingsDisplayPage.add(settingsWindowModeDropdown);
        settingsDisplayPage.add(sizeRow);
        settingsDisplayPage.add(settingsVsyncToggle);

        settingsUiPage = new UiVBox(0.0f, 0.0f, 0.0f, settingsPageHeight, contentSpacing);
        settingsUiPage.setLayoutHint(0.0f, settingsPageHeight, 0.0f, settingsPageHeight, float.max, settingsPageHeight, 1.0f, 0.0f);
        settingsUiPage.add(settingsScaleSlider);
        settingsUiPage.add(settingsThemeDropdown);
        settingsUiPage.add(settingsCompactToggle);

        settingsAudioPage = new UiVBox(0.0f, 0.0f, 0.0f, settingsPageHeight, contentSpacing);
        settingsAudioPage.setLayoutHint(0.0f, settingsPageHeight, 0.0f, settingsPageHeight, float.max, settingsPageHeight, 1.0f, 0.0f);
        settingsAudioPage.add(settingsMasterVolumeSlider);
        settingsAudioPage.add(settingsMusicVolumeSlider);
        settingsAudioPage.add(settingsEffectsVolumeSlider);

        settingsPageBox = new UiContentBox(0.0f, 0.0f, 0.0f, settingsPageHeight);
        settingsPageBox.setLayoutHint(0.0f, settingsPageHeight, 0.0f, settingsPageHeight, float.max, settingsPageHeight, 1.0f, 0.0f);
        settingsPageBox.add(settingsDisplayPage);
        settingsPageBox.add(settingsUiPage);
        settingsPageBox.add(settingsAudioPage);

        settingsBody.add(settingsTitleLabel);
        settingsBody.add(settingsIntroLabel);
        settingsBody.add(settingsProfileLabel);
        settingsBody.add(settingsTabBar);
        settingsBody.add(settingsPageBox);

        settingsActionRow = new UiHBox(0.0f, 0.0f, 0.0f, 0.0f, contentSpacing);
        settingsActionRow.add(settingsApplyButton);
        settingsActionRow.add(settingsSaveButton);

        settingsContent.add(settingsBody);
        settingsContent.add(settingsActionRow);
        settingsWindow.add(settingsContent);
        settingsWindow.visible = false;
        settingsWindow.onClose = ()
        {
            hideWindow(settingsWindow);
            logLine("UiWindow close: Settings");
        };
        registerWindowInteractionHandlers(settingsWindow);
        addWindow(settingsWindow);
        updateSettingsPageVisibility();
        refreshSettingsControls();
    }

    void refreshSettingsControls()
    {
        if (settingsWindowModeDropdown is null)
            return;

        settingsWindowModeDropdown.selectedIndex = optionIndex(settingsWindowModeDropdown.options, settingsDraft.display.windowMode);
        settingsWidthField.setText(format("%u", settingsDraft.display.windowWidth));
        settingsHeightField.setText(format("%u", settingsDraft.display.windowHeight));
        settingsVsyncToggle.checked = settingsDraft.display.vsync;
        settingsScaleSlider.value = settingsDraft.display.scale;
        settingsThemeDropdown.selectedIndex = optionIndex(settingsThemeDropdown.options, settingsDraft.ui.theme);
        settingsCompactToggle.checked = settingsDraft.ui.compactWindows;
        settingsMasterVolumeSlider.value = settingsDraft.audio.masterVolume;
        settingsMusicVolumeSlider.value = settingsDraft.audio.musicVolume;
        settingsEffectsVolumeSlider.value = settingsDraft.audio.effectsVolume;
        updateSettingsSummary();
    }

    void applySettingsFromDialog()
    {
        syncSettingsDraftFromControls();
        if (onApplySettings !is null)
            onApplySettings();
    }

    void saveSettingsFromDialog()
    {
        syncSettingsDraftFromControls();
        if (onSaveSettings !is null)
            onSaveSettings();
    }

    void syncSettingsDraftFromControls()
    {
        if (settingsWindowModeDropdown is null)
            return;

        settingsDraft.display.windowMode = settingsWindowModeDropdown.selectedText();
        settingsDraft.display.windowWidth = parseUintSetting(settingsWidthField.text, settingsDraft.display.windowWidth);
        settingsDraft.display.windowHeight = parseUintSetting(settingsHeightField.text, settingsDraft.display.windowHeight);
        settingsDraft.display.vsync = settingsVsyncToggle.checked;
        settingsDraft.display.scale = settingsScaleSlider.value;
        settingsDraft.ui.theme = settingsThemeDropdown.selectedText();
        settingsDraft.ui.compactWindows = settingsCompactToggle.checked;
        settingsDraft.audio.masterVolume = settingsMasterVolumeSlider.value;
        settingsDraft.audio.musicVolume = settingsMusicVolumeSlider.value;
        settingsDraft.audio.effectsVolume = settingsEffectsVolumeSlider.value;
        updateSettingsSummary();
    }

    void previewAudioSettingsFromDialog(DemoAudioPreviewKind kind)
    {
        updateSettingsSummary();
        if (onPreviewAudioSettings !is null)
            onPreviewAudioSettings(kind);
    }

    void updateSettingsPageVisibility()
    {
        if (settingsDisplayPage is null)
            return;

        settingsDisplayPage.visible = settingsTabBar.selectedIndex == 0;
        settingsUiPage.visible = settingsTabBar.selectedIndex == 1;
        settingsAudioPage.visible = settingsTabBar.selectedIndex == 2;
    }

    void openDropdownPopup(UiDropdown dropdown, float anchorX, float anchorY, float anchorWidth, float anchorHeight)
    {
        if (dropdown is null || dropdown.options.length == 0)
            return;

        if (dropdownPopupWindow !is null)
        {
            removeWindow(dropdownPopupWindow);
            dropdownPopupWindow = null;
        }

        const listHeight = cast(float)dropdown.options.length * dropdownPopupRowHeight;
        const popupHeight = listHeight + 6.0f;
        dropdownPopupWindow = new UiWindow("Dropdown", anchorX, anchorY + anchorHeight, anchorWidth, popupHeight, cast(float[4])settingsBodyColor, cast(float[4])settingsHeaderColor, cast(float[4])settingsTitleColor, false, false, false, 0.0f, 0.0f, 0.0f, 0.0f);
        dropdownPopupWindow.setChromeFlags(false, false, false, false);
        dropdownPopupWindow.setChromeVisibility(false, false, true);

        auto list = new UiListBox(dropdown.options, dropdown.selectedIndex, 0.0f, 0.0f, anchorWidth, listHeight, UiTextStyle.medium, dropdownPopupRowHeight);
        list.setLayoutHint(anchorWidth, listHeight, anchorWidth, listHeight, float.max, listHeight, 1.0f, 0.0f);
        list.onActivated = (index, value)
        {
            dropdown.selectIndex(index);
            dismissActivePopup();
            setFocusedWidget(dropdown);
        };

        dropdownPopupWindow.add(list);
        showPopupWindow(dropdownPopupWindow, anchorX, anchorY, anchorWidth, anchorHeight);
        setFocusedWidget(list);
    }

    void updateSettingsSummary()
    {
        if (settingsProfileLabel is null)
            return;

        settingsProfileLabel.text = format("Profil: %s, %ux%u, Theme %s", settingsDraft.display.windowMode, settingsDraft.display.windowWidth, settingsDraft.display.windowHeight, settingsDraft.ui.theme);
    }

    static size_t optionIndex(string[] options, string value)
    {
        foreach (index, option; options)
        {
            if (option == value)
                return index;
        }

        return 0;
    }

    static uint parseUintSetting(string value, uint fallback)
    {
        try
        {
            return to!uint(value);
        }
        catch (ConvException)
        {
            return fallback;
        }
        catch (Exception)
        {
            return fallback;
        }
    }

    void updateStatusText(float fps, string currentShapeName, string currentRenderModeName, string buildVersion, float yawDegrees, float pitchDegrees)
    {
        statusBuildLabel.text = format("Build: %s", buildVersion);
        statusFpsLabel.text = format("FPS: %.1f", fps);
        statusSceneLabel.text = format("Szene: %s", currentShapeName);
        statusModeLabel.text = format("Modus: %s", currentRenderModeName);
        statusRotationLabel.text = format("Rotation: Yaw %.1f deg, Pitch %.1f deg", yawDegrees, pitchDegrees);
        statusViewportLabel.text = format("Viewport: %.0f x %.0f", viewportWidth, viewportHeight);
        updateOpenDemoWindowCountLabel();
        updateSettingsSummary();
    }

    uint openDemoWindowCount() const
    {
        return cast(uint)(testWindows.length + chromeWindows.length + inputWindows.length + selectionWindows.length + audioWindows.length);
    }

    void updateOpenDemoWindowCountLabel()
    {
        if (helpIntroLabel !is null)
            helpIntroLabel.text = format("Open demo windows: %u", openDemoWindowCount());
    }

    override void anchorWindows()
    {
        if (sidebarWindow !is null)
        {
            sidebarWindow.x = 0.0f;
            sidebarWindow.y = 0.0f;
            sidebarWindow.width = currentSidebarWidth();
            sidebarWindow.height = viewportHeight > 0.0f ? viewportHeight : sidebarFallbackHeight;
        }

        if (!helpAnchored)
        {
            helpWindow.x = sidebarReservedLeft();
            helpWindow.y = windowMargin;
            helpAnchored = true;
        }

        if (!statusAnchored)
        {
            statusWindow.x = viewportWidth > statusWindow.width + sidebarReservedLeft() ? viewportWidth - statusWindow.width : sidebarReservedLeft();
            statusWindow.y = windowMargin;
            statusAnchored = true;
        }

        if (!settingsAnchored)
        {
            settingsWindow.x = viewportWidth > settingsWindow.width + sidebarReservedLeft() ? viewportWidth - settingsWindow.width - windowMargin : sidebarReservedLeft();
            settingsWindow.y = viewportHeight > settingsWindow.height ? viewportHeight - settingsWindow.height - windowMargin : windowMargin;
            settingsAnchored = true;
        }

        foreach (index, demoWindow; testWindows)
        {
            const offset = windowMargin + cast(float)index * 22.0f;
            if (demoWindow.window.x <= 0.0f && demoWindow.window.y <= 0.0f)
            {
                demoWindow.window.x = max(windowMargin * 2.0f + offset, windowMargin);
                demoWindow.window.y = max(windowMargin * 2.0f + offset, windowMargin);
            }
        }

        foreach (index, demoWindow; chromeWindows)
        {
            const offset = windowMargin + cast(float)(testWindows.length + index) * 22.0f;
            if (demoWindow.window.x <= 0.0f && demoWindow.window.y <= 0.0f)
            {
                demoWindow.window.x = max(windowMargin * 2.0f + offset, windowMargin);
                demoWindow.window.y = max(windowMargin * 2.0f + offset, windowMargin);
            }
        }
    }

    void spawnLayoutTestWindow()
    {
        LayoutDemoWindow demoWindow = buildLayoutDemoWindow(nextTestWindowSerial++, &openDropdownPopup);
        const cascadeIndex = cast(float)(nextTestWindowSerial - 2);
        demoWindow.window.x += cascadeIndex * 28.0f;
        demoWindow.window.y += cascadeIndex * 24.0f;
        autoSizeWindow(demoWindow.window, demoWindow.content, windowContentPaddingX, windowContentPaddingY, windowContentPaddingX, windowContentPaddingY, testWindowWidth, testWindowHeight);
        demoWindow.window.onClose = ()
        {
            demoWindow.window.visible = false;
            removeLayoutDemoWindow(demoWindow);
            logLine("UiWindow close: ", demoWindow.window.title);
        };
        registerWindowInteractionHandlers(demoWindow.window);
        testWindows ~= demoWindow;
        addWindow(demoWindow.window);
        if (viewportWidth > 0.0f && viewportHeight > 0.0f)
        {
            ensureWindowLayout();
            placeWindowWithoutOverlap(demoWindow.window);
        }
        logLine("UiWindow spawn: ", demoWindow.window.title);
        updateOpenDemoWindowCountLabel();
    }

    void removeLayoutDemoWindow(LayoutDemoWindow demoWindow)
    {
        if (demoWindow is null)
            return;

        for (size_t index = 0; index < testWindows.length; ++index)
        {
            if (testWindows[index] is demoWindow)
            {
                testWindows = testWindows[0 .. index] ~ testWindows[index + 1 .. $];
                break;
            }
        }

        removeWindow(demoWindow.window);
        updateOpenDemoWindowCountLabel();
    }

    void spawnChromeDemoWindow()
    {
        ChromeDemoWindow demoWindow = new ChromeDemoWindow(nextChromeWindowSerial++);
        const cascadeIndex = cast(float)(nextChromeWindowSerial - 2);
        demoWindow.window.x += cascadeIndex * 28.0f;
        demoWindow.window.y += cascadeIndex * 24.0f;
        autoSizeWindow(demoWindow.window, demoWindow.content, windowContentPaddingX, windowContentPaddingY, windowContentPaddingX, windowContentPaddingY, 360.0f, 320.0f);
        demoWindow.window.onClose = ()
        {
            demoWindow.window.visible = false;
            removeChromeDemoWindow(demoWindow);
            logLine("UiWindow close: ", demoWindow.window.title);
        };
        registerWindowInteractionHandlers(demoWindow.window);
        chromeWindows ~= demoWindow;
        addWindow(demoWindow.window);
        if (viewportWidth > 0.0f && viewportHeight > 0.0f)
        {
            ensureWindowLayout();
            placeWindowWithoutOverlap(demoWindow.window);
        }
        logLine("UiWindow spawn: ", demoWindow.window.title);
        updateOpenDemoWindowCountLabel();
    }

    void removeChromeDemoWindow(ChromeDemoWindow demoWindow)
    {
        if (demoWindow is null)
            return;

        for (size_t index = 0; index < chromeWindows.length; ++index)
        {
            if (chromeWindows[index] is demoWindow)
            {
                chromeWindows = chromeWindows[0 .. index] ~ chromeWindows[index + 1 .. $];
                break;
            }
        }

        removeWindow(demoWindow.window);
        updateOpenDemoWindowCountLabel();
    }

    void spawnInputDemoWindow()
    {
        InputDemoWindow demoWindow = new InputDemoWindow(nextInputWindowSerial++, &openDropdownPopup);
        const cascadeIndex = cast(float)(nextInputWindowSerial - 2);
        demoWindow.window.x += cascadeIndex * 28.0f;
        demoWindow.window.y += cascadeIndex * 24.0f;
        autoSizeWindow(demoWindow.window, demoWindow.content, windowContentPaddingX, windowContentPaddingY, windowContentPaddingX, windowContentPaddingY, 420.0f, 286.0f);
        demoWindow.window.onClose = ()
        {
            demoWindow.window.visible = false;
            removeInputDemoWindow(demoWindow);
            logLine("UiWindow close: ", demoWindow.window.title);
        };
        registerWindowInteractionHandlers(demoWindow.window);
        inputWindows ~= demoWindow;
        addWindow(demoWindow.window);
        if (viewportWidth > 0.0f && viewportHeight > 0.0f)
        {
            ensureWindowLayout();
            placeWindowWithoutOverlap(demoWindow.window);
        }
        logLine("UiWindow spawn: ", demoWindow.window.title);
        updateOpenDemoWindowCountLabel();
    }

    void removeInputDemoWindow(InputDemoWindow demoWindow)
    {
        if (demoWindow is null)
            return;

        for (size_t index = 0; index < inputWindows.length; ++index)
        {
            if (inputWindows[index] is demoWindow)
            {
                inputWindows = inputWindows[0 .. index] ~ inputWindows[index + 1 .. $];
                break;
            }
        }

        removeWindow(demoWindow.window);
        updateOpenDemoWindowCountLabel();
    }

    void spawnSelectionDemoWindow()
    {
        SelectionDemoWindow demoWindow = new SelectionDemoWindow(nextSelectionWindowSerial++, &openDropdownPopup);
        const cascadeIndex = cast(float)(nextSelectionWindowSerial - 2);
        demoWindow.window.x += cascadeIndex * 28.0f;
        demoWindow.window.y += cascadeIndex * 24.0f;
        autoSizeWindow(demoWindow.window, demoWindow.content, windowContentPaddingX, windowContentPaddingY, windowContentPaddingX, windowContentPaddingY, 430.0f, 278.0f);
        demoWindow.window.onClose = ()
        {
            demoWindow.window.visible = false;
            removeSelectionDemoWindow(demoWindow);
            logLine("UiWindow close: ", demoWindow.window.title);
        };
        registerWindowInteractionHandlers(demoWindow.window);
        selectionWindows ~= demoWindow;
        addWindow(demoWindow.window);
        if (viewportWidth > 0.0f && viewportHeight > 0.0f)
        {
            ensureWindowLayout();
            placeWindowWithoutOverlap(demoWindow.window);
        }
        logLine("UiWindow spawn: ", demoWindow.window.title);
        updateOpenDemoWindowCountLabel();
    }

    void removeSelectionDemoWindow(SelectionDemoWindow demoWindow)
    {
        if (demoWindow is null)
            return;

        for (size_t index = 0; index < selectionWindows.length; ++index)
        {
            if (selectionWindows[index] is demoWindow)
            {
                selectionWindows = selectionWindows[0 .. index] ~ selectionWindows[index + 1 .. $];
                break;
            }
        }

        removeWindow(demoWindow.window);
        updateOpenDemoWindowCountLabel();
    }

    void spawnAudioDemoWindow()
    {
        AudioDemoWindow demoWindow = new AudioDemoWindow(nextAudioWindowSerial++);
        const cascadeIndex = cast(float)(nextAudioWindowSerial - 2);
        demoWindow.window.x += cascadeIndex * 28.0f;
        demoWindow.window.y += cascadeIndex * 24.0f;
        autoSizeWindow(demoWindow.window, demoWindow.content, windowContentPaddingX, windowContentPaddingY, windowContentPaddingX, windowContentPaddingY, 384.0f, 230.0f);
        demoWindow.onAudioEvent = (kind)
        {
            if (onPreviewAudioSettings !is null)
                onPreviewAudioSettings(kind);
        };
        demoWindow.window.onClose = ()
        {
            demoWindow.window.visible = false;
            removeAudioDemoWindow(demoWindow);
            logLine("UiWindow close: ", demoWindow.window.title);
        };
        registerWindowInteractionHandlers(demoWindow.window);
        audioWindows ~= demoWindow;
        addWindow(demoWindow.window);
        if (viewportWidth > 0.0f && viewportHeight > 0.0f)
        {
            ensureWindowLayout();
            placeWindowWithoutOverlap(demoWindow.window);
        }
        logLine("UiWindow spawn: ", demoWindow.window.title);
        updateOpenDemoWindowCountLabel();
    }

    void removeAudioDemoWindow(AudioDemoWindow demoWindow)
    {
        if (demoWindow is null)
            return;

        for (size_t index = 0; index < audioWindows.length; ++index)
        {
            if (audioWindows[index] is demoWindow)
            {
                audioWindows = audioWindows[0 .. index] ~ audioWindows[index + 1 .. $];
                break;
            }
        }

        removeWindow(demoWindow.window);
        updateOpenDemoWindowCountLabel();
    }

    void closeAllDemoWindows()
    {
        dismissActivePopup();

        hideWindow(helpWindow, false);
        hideWindow(statusWindow, false);
        hideWindow(settingsWindow, false);

        while (testWindows.length > 0)
            removeLayoutDemoWindow(testWindows[$ - 1]);
        while (chromeWindows.length > 0)
            removeChromeDemoWindow(chromeWindows[$ - 1]);
        while (inputWindows.length > 0)
            removeInputDemoWindow(inputWindows[$ - 1]);
        while (selectionWindows.length > 0)
            removeSelectionDemoWindow(selectionWindows[$ - 1]);
        while (audioWindows.length > 0)
            removeAudioDemoWindow(audioWindows[$ - 1]);

        if (sidebarWindow !is null)
            bringWindowToFront(sidebarWindow);
        updateOpenDemoWindowCountLabel();
        logLine("UiSidebar close all windows");
    }
}

@("DemoUiScreen spawns and toggles the rebuilt windows")
unittest
{
    DemoUiScreen screen = new DemoUiScreen();
    screen.initialize([]);
    screen.syncViewport(800.0f, 600.0f, 0.0f, "test", "test", "test");

    assert(screen.containsPointer(20.0f, 20.0f));
    screen.toggleSettingsWindow();
    assert(screen.settingsWindow.visible);
    screen.toggleSettingsWindow();
    assert(!screen.settingsWindow.acceptsInput());
    foreach (_; 0 .. 2)
        screen.tickUi(0.05f);
    assert(!screen.settingsWindow.visible);
    screen.spawnLayoutTestWindow();
    assert(screen.windowsInFrontToBack().length >= 5);
    screen.spawnChromeDemoWindow();
    assert(screen.windowsInFrontToBack().length >= 6);
    screen.spawnInputDemoWindow();
    assert(screen.windowsInFrontToBack().length >= 7);
    screen.spawnSelectionDemoWindow();
    assert(screen.windowsInFrontToBack().length >= 8);
    screen.spawnAudioDemoWindow();
    assert(screen.windowsInFrontToBack().length >= 9);
}

@("DemoUiScreen sidebar reveals and spawns demo windows")
unittest
{
    DemoUiScreen screen = new DemoUiScreen();
    screen.initialize([]);
    screen.syncViewport(800.0f, 600.0f, 0.0f, "test", "test", "test");

    assert(screen.sidebarWindow.visible);
    assert(screen.sidebarWindow.x == 0.0f);
    assert(screen.sidebarWindow.y == 0.0f);
    assert(screen.sidebarWindow.width == sidebarCollapsedWidth);
    assert(screen.sidebarWindow.height == 600.0f);
    UiLayoutContext context;
    screen.sidebarWindow.layoutWindow(context);
    assert(screen.sidebarHelpButton.width == sidebarCollapsedWidth - sidebarPadding * 2.0f);
    assert(screen.sidebarStatusButton.y > screen.sidebarAudioButton.y);
    assert(screen.sidebarExitButton.y + screen.sidebarExitButton.height == screen.sidebarWindow.height - sidebarPadding, format("exit bottom %.1f, sidebar target %.1f", screen.sidebarExitButton.y + screen.sidebarExitButton.height, screen.sidebarWindow.height - sidebarPadding));
    assert(screen.helpWindow.x >= screen.sidebarReservedLeft(), format("help x %.1f, reserved %.1f", screen.helpWindow.x, screen.sidebarReservedLeft()));
    assert(screen.helpShapeLabel.text == "+/- switch 3D model; F/T/W/H switch render modes.");
    assert(screen.helpFocusLabel.text == "Tab/Shift+Tab move focus; Enter activates controls; D toggles UI bounds.");

    assert(!screen.helpWindow.visible);
    screen.sidebarHelpButton.onClick();
    assert(screen.helpWindow.visible);
    screen.sidebarHelpButton.onClick();
    assert(!screen.helpWindow.acceptsInput());
    foreach (_; 0 .. 2)
        screen.tickUi(0.05f);
    assert(!screen.helpWindow.visible);

    assert(!screen.statusWindow.visible);
    screen.sidebarStatusButton.onClick();
    assert(screen.statusWindow.visible);
    screen.sidebarStatusButton.onClick();
    assert(!screen.statusWindow.acceptsInput());
    foreach (_; 0 .. 2)
        screen.tickUi(0.05f);
    assert(!screen.statusWindow.visible);

    assert(!screen.settingsWindow.visible);
    screen.sidebarSettingsButton.onClick();
    assert(screen.settingsWindow.visible);
    screen.sidebarSettingsButton.onClick();
    assert(!screen.settingsWindow.acceptsInput());
    foreach (_; 0 .. 2)
        screen.tickUi(0.05f);
    assert(!screen.settingsWindow.visible);

    const testCount = screen.testWindows.length;
    screen.sidebarWidgetButton.onClick();
    assert(screen.testWindows.length == testCount + 1);

    const chromeCount = screen.chromeWindows.length;
    screen.sidebarChromeButton.onClick();
    assert(screen.chromeWindows.length == chromeCount + 1);

    const inputCount = screen.inputWindows.length;
    screen.sidebarInputButton.onClick();
    assert(screen.inputWindows.length == inputCount + 1);
    auto inputDemo = screen.inputWindows[$ - 1];
    inputDemo.nameField.setText("abc");
    inputDemo.applyButton.onClick();
    assert(inputDemo.summaryLabel.text.canFind("abc"));
    assert(inputDemo.summaryLabel.text.canFind("apply=1"));

    const selectionCount = screen.selectionWindows.length;
    screen.sidebarSelectionButton.onClick();
    assert(screen.selectionWindows.length == selectionCount + 1);
    auto selectionDemo = screen.selectionWindows[$ - 1];
    selectionDemo.listBox.selectIndex(2);
    assert(selectionDemo.summaryLabel.text.canFind("Gamma"));

    const audioCount = screen.audioWindows.length;
    uint audioEvents;
    DemoAudioPreviewKind audioKind;
    screen.onPreviewAudioSettings = (kind) { ++audioEvents; audioKind = kind; };
    screen.sidebarAudioButton.onClick();
    assert(screen.audioWindows.length == audioCount + 1);
    screen.audioWindows[$ - 1].uiClickButton.onClick();
    assert(audioEvents == 1);
    assert(audioKind == DemoAudioPreviewKind.ui);

    screen.sidebarHelpButton.onClick();
    screen.sidebarStatusButton.onClick();
    screen.sidebarSettingsButton.onClick();
    assert(screen.helpWindow.visible);
    assert(screen.statusWindow.visible);
    assert(screen.settingsWindow.visible);

    screen.sidebarCloseAllButton.onClick();
    assert(!screen.helpWindow.visible);
    assert(!screen.statusWindow.visible);
    assert(!screen.settingsWindow.visible);
    assert(screen.testWindows.length == 0);
    assert(screen.chromeWindows.length == 0);
    assert(screen.inputWindows.length == 0);
    assert(screen.selectionWindows.length == 0);
    assert(screen.audioWindows.length == 0);
    assert(screen.helpIntroLabel.text == "Open demo windows: 0");

    assert(!screen.quitRequested);
    screen.sidebarExitButton.onClick();
    assert(screen.quitRequested);
}

@("DemoUiScreen tabs through dropdowns and activates sidebar exit")
unittest
{
    DemoUiScreen screen = new DemoUiScreen();
    screen.initialize([]);
    screen.syncViewport(800.0f, 600.0f, 0.0f, "test", "test", "test");
    screen.toggleSettingsWindow();

    UiKeyEvent event;
    event.kind = UiKeyEventKind.keyDown;
    event.key = UiKeyCode.tab;

    bool reachedDropdown;
    foreach (_; 0 .. 80)
    {
        assert(screen.dispatchKeyEvent(event));
        if (screen.currentFocusedWidget() is screen.settingsWindowModeDropdown)
        {
            reachedDropdown = true;
            break;
        }
    }
    assert(reachedDropdown);

    foreach (_; 0 .. 80)
    {
        assert(screen.dispatchKeyEvent(event));
        if (screen.currentFocusedWidget() is screen.sidebarExitButton)
            break;
    }
    assert(screen.currentFocusedWidget() is screen.sidebarExitButton);

    event.key = UiKeyCode.enter;
    assert(screen.dispatchKeyEvent(event));
    assert(screen.quitRequested);
}

@("DemoUiScreen opens dropdown popups for settings selections")
unittest
{
    DemoUiScreen screen = new DemoUiScreen();
    screen.initialize([]);
    screen.syncViewport(800.0f, 600.0f, 0.0f, "test", "test", "test");

    screen.openDropdownPopup(screen.settingsThemeDropdown, 300.0f, 200.0f, 220.0f, 28.0f);

    assert(screen.hasActivePopup());
    assert(screen.dropdownPopupWindow !is null);
    assert(screen.dropdownPopupWindow.visible);
    assert(screen.windowsInFrontToBack()[$ - 1] is screen.dropdownPopupWindow);

    UiPointerEvent event;
    event.kind = UiPointerEventKind.buttonDown;
    event.button = 1;
    event.x = 310.0f;
    event.y = 238.0f;

    assert(screen.dispatchPointerEvent(event));
    assert(screen.settingsThemeDropdown.selectedText() == "midnight");
    assert(screen.settingsDraft.ui.theme == "midnight");

    assert(!screen.hasActivePopup());
}

@("DemoUiScreen keeps keyboard focus inside open dropdown popups")
unittest
{
    DemoUiScreen screen = new DemoUiScreen();
    screen.initialize([]);
    screen.syncViewport(800.0f, 600.0f, 0.0f, "test", "test", "test");

    screen.settingsThemeDropdown.selectIndex(0);
    screen.openDropdownPopup(screen.settingsThemeDropdown, 300.0f, 200.0f, 220.0f, 28.0f);

    assert(screen.hasActivePopup());
    auto popupFocus = screen.currentFocusedWidget();
    assert(popupFocus !is null);

    UiKeyEvent keyEvent;
    keyEvent.kind = UiKeyEventKind.keyDown;
    keyEvent.key = UiKeyCode.tab;
    assert(screen.dispatchKeyEvent(keyEvent));
    assert(screen.currentFocusedWidget() is popupFocus);
    assert(screen.hasActivePopup());

    keyEvent.key = UiKeyCode.down;
    assert(screen.dispatchKeyEvent(keyEvent));
    keyEvent.key = UiKeyCode.enter;
    assert(screen.dispatchKeyEvent(keyEvent));

    assert(screen.settingsThemeDropdown.selectedText() == "classic");
    assert(screen.settingsDraft.ui.theme == "classic");
    assert(!screen.hasActivePopup());
    assert(screen.currentFocusedWidget() is screen.settingsThemeDropdown);
}

@("DemoUiScreen switches settings pages with tabs")
unittest
{
    DemoUiScreen screen = new DemoUiScreen();
    screen.initialize([]);
    screen.syncViewport(800.0f, 600.0f, 0.0f, "test", "test", "test");

    assert(screen.settingsDisplayPage.visible);
    assert(!screen.settingsUiPage.visible);
    assert(!screen.settingsAudioPage.visible);

    screen.settingsTabBar.selectIndex(2);
    assert(!screen.settingsDisplayPage.visible);
    assert(!screen.settingsUiPage.visible);
    assert(screen.settingsAudioPage.visible);

    uint previews;
    DemoAudioPreviewKind lastPreview;
    screen.onPreviewAudioSettings = (kind) { ++previews; lastPreview = kind; };
    screen.settingsMasterVolumeSlider.setValue(0.42f);
    assert(screen.settingsDraft.audio.masterVolume > 0.41f && screen.settingsDraft.audio.masterVolume < 0.43f);
    assert(previews == 0);
    screen.previewAudioSettingsFromDialog(DemoAudioPreviewKind.master);
    assert(previews == 1);
    assert(lastPreview == DemoAudioPreviewKind.master);
}

@("DemoUiScreen shows rotation in status window")
unittest
{
    DemoUiScreen screen = new DemoUiScreen();
    screen.initialize([]);
    screen.syncViewport(800.0f, 600.0f, 0.0f, "test", "test", "test", 12.5f, -7.25f);

    assert(screen.statusRotationLabel.text == "Rotation: Yaw 12.5 deg, Pitch -7.2 deg");
    assert(!screen.statusWindow.showHeader);
    assert(!screen.statusWindow.showBorder);
    assert(!screen.statusWindow.showBackfill);
    assert(screen.statusWindow.pinRight);
    assert(screen.statusWindow.pinTop);
    assert(screen.statusWindow.x == 800.0f - screen.statusWindow.width);
    assert(screen.statusWindow.y == windowMargin);
}

@("DemoUiScreen sidebar expands labels and reserves width")
unittest
{
    DemoUiScreen screen = new DemoUiScreen();
    screen.initialize([]);
    screen.syncViewport(800.0f, 600.0f, 0.0f, "test", "test", "test");

    assert(!screen.sidebarExpanded);
    assert(screen.sidebarWindow.width == sidebarCollapsedWidth);
    const collapsedReserved = screen.sidebarReservedLeft();
    assert(screen.helpWindow.x >= collapsedReserved);

    screen.sidebarExpandButton.onClick();
    assert(screen.sidebarExpanded);
    assert(screen.sidebarWindow.width == sidebarExpandedWidth);
    assert(screen.sidebarReservedLeft() > collapsedReserved);
    assert(screen.helpWindow.x >= screen.sidebarReservedLeft(), format("help x %.1f, reserved %.1f", screen.helpWindow.x, screen.sidebarReservedLeft()));
    assert(screen.sidebarHelpButton.caption == "?  Help Desk");
    assert(screen.sidebarInputButton.caption == "I  Input");
    assert(screen.sidebarAudioButton.caption == "A  Audio");
    assert(screen.sidebarStatusButton.caption == "S  Status");
    assert(screen.sidebarCloseAllButton.caption == "All Close");
    assert(screen.sidebarExitButton.caption == "X  Exit");
    UiLayoutContext context;
    screen.sidebarWindow.layoutWindow(context);
    assert(screen.sidebarHelpButton.width == sidebarExpandedWidth - sidebarPadding * 2.0f);
    assert(screen.sidebarStatusButton.y > screen.sidebarAudioButton.y);
    assert(screen.sidebarCloseAllButton.y > screen.sidebarSettingsButton.y);
    assert(screen.sidebarExitButton.y + screen.sidebarExitButton.height == screen.sidebarWindow.height - sidebarPadding, format("exit bottom %.1f, sidebar target %.1f", screen.sidebarExitButton.y + screen.sidebarExitButton.height, screen.sidebarWindow.height - sidebarPadding));

    screen.sidebarExpandButton.onClick();
    assert(!screen.sidebarExpanded);
    assert(screen.sidebarWindow.width == sidebarCollapsedWidth);
    assert(screen.sidebarHelpButton.caption == "?");
    assert(screen.sidebarInputButton.caption == "I");
    assert(screen.sidebarAudioButton.caption == "A");
    assert(screen.sidebarStatusButton.caption == "S");
    assert(screen.sidebarCloseAllButton.caption == "All");
    assert(screen.sidebarExitButton.caption == "X");
    screen.sidebarWindow.layoutWindow(context);
    assert(screen.sidebarHelpButton.width == sidebarCollapsedWidth - sidebarPadding * 2.0f);
    assert(screen.sidebarStatusButton.y > screen.sidebarAudioButton.y);
    assert(screen.sidebarCloseAllButton.y > screen.sidebarSettingsButton.y);
    assert(screen.sidebarExitButton.y + screen.sidebarExitButton.height == screen.sidebarWindow.height - sidebarPadding, format("exit bottom %.1f, sidebar target %.1f", screen.sidebarExitButton.y + screen.sidebarExitButton.height, screen.sidebarWindow.height - sidebarPadding));
}

@("DemoUiScreen sidebar shrinks vertically after a larger layout")
unittest
{
    DemoUiScreen screen = new DemoUiScreen();
    screen.initialize([]);
    screen.syncViewport(1024.0f, 720.0f, 0.0f, "test", "test", "test");

    UiLayoutContext context;
    screen.sidebarWindow.layoutWindow(context);
    assert(screen.sidebarExitButton.y + screen.sidebarExitButton.height == screen.sidebarWindow.height - sidebarPadding, format("exit bottom %.1f, sidebar target %.1f", screen.sidebarExitButton.y + screen.sidebarExitButton.height, screen.sidebarWindow.height - sidebarPadding));

    screen.syncViewport(1024.0f, 576.0f, 0.0f, "test", "test", "test");
    screen.sidebarWindow.layoutWindow(context);
    assert(screen.sidebarWindow.height == 576.0f);
    assert(screen.sidebarExitButton.y + screen.sidebarExitButton.height == screen.sidebarWindow.height - sidebarPadding, format("exit bottom %.1f, sidebar target %.1f", screen.sidebarExitButton.y + screen.sidebarExitButton.height, screen.sidebarWindow.height - sidebarPadding));
}
