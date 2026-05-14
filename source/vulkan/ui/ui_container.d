/** Root container for retained UI trees.
 *
 * The container itself does not render a background; it only forwards to its
 * children.
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.ui.ui_container;

import vulkan.ui.ui_context : UiRenderContext;
import vulkan.ui.ui_widget : UiWidget;

/** Root container that only renders its children. */
final class UiContainer : UiWidget
{
    this()
    {
        super(0, 0, 0, 0);
        childOffsetX = 0.0f;
        childOffsetY = 0.0f;
    }

protected:
    override void renderSelf(ref UiRenderContext context)
    {
    }
}
