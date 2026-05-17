# Asset And Localization Pipeline

This document records the project decision for authored images, 3D model assets, and localization data. The goal is to move from hand-written demo placeholders toward common editor-friendly formats without leaking decoder details into UI widgets or renderer-facing engine APIs.

## 2D Images And UI Icons

Project decision:

- use PNG as the normal authored 2D image format
- keep PPM only as a tiny fallback, test fixture, and debug format
- decode all loaded images into an engine-owned `RGBA8` image representation before upload
- keep `UiImage` and other widgets asset-id based; widgets should not know whether an asset was loaded from PNG, PPM, or a future package file

PNG is the most useful default for UI icons, image previews, sprites, and simple textured demo assets. It supports lossless compression, broad editor/tool support, and real alpha channels. That makes it practical for GIMP, Krita, Inkscape, Blender exports, Aseprite, and other normal art workflows. PPM is still useful because it is trivial to inspect and load, but it is not a serious production asset format.

The first loader should produce one neutral runtime structure:

```text
ImageData
  width
  height
  rgba8Pixels
```

The renderer can then upload that data into the existing Vulkan texture path or copy it into a UI atlas. The asset layer owns decoding, format conversion, error logging, and fallback selection.

Loader options:

- SDL_image is the preferred first practical loader because the project already uses SDL through BindBC. It can load common image formats and lets the engine normalize the result to RGBA8.
- `stb_image` is a small alternative when a single-file C decoder is preferable, but it adds a separate C integration path.
- KTX2 is a later production texture-container option for GPU-oriented textures, mip levels, and compressed texture delivery. It should not block the first PNG-based UI asset pass.

Useful references:

- PNG specification: https://www.w3.org/TR/png-3/
- Khronos KTX texture container: https://www.khronos.org/ktx
- BindBC SDL notes for SDL_image bindings: https://github.com/BindBC/bindbc-sdl

## 3D Models

Project decision:

- use glTF 2.0 as the normal 3D asset format
- prefer `.glb` for compact demo assets
- allow `.gltf` plus external `.bin` and texture files when separate asset files are useful during authoring
- use Blender as the main editor/export path

glTF is a runtime-oriented transmission format for 3D scenes and models. It is a better fit for an engine demo than hand-written meshes or source-code-only object definitions because it can carry mesh data, node hierarchy, materials, textures, animation data, and metadata through a common pipeline. The first engine loader does not need to support all of glTF at once. It should start with static meshes, indices, positions, normals, UVs, base material data, and referenced textures.

Recommended implementation order:

1. Add an asset module that loads a single `.glb` or `.gltf` file into neutral engine structures.
2. Support static indexed triangle meshes with positions, normals, UVs, and one material.
3. Resolve texture references through the same image-loading path used by UI images.
4. Add node transforms and multiple meshes.
5. Add animation, skinning, cameras, and glTF extensions later.

Loader options:

- A small D glTF loader such as `gltf2loader` can be evaluated first because it matches the project language.
- C loaders such as `cgltf` or C++ loaders such as `tinygltf` are common alternatives when D package coverage is not enough.
- Assimp supports many formats, but it is probably too broad and heavy for the current minimal engine direction.

Useful authoring and sample sources:

- Blender glTF import/export manual: https://docs.blender.org/manual/en/latest/addons/import_export/scene_gltf2.html
- Khronos glTF overview: https://www.khronos.org/gltf/
- glTF 2.0 specification: https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html
- Khronos glTF sample assets: https://github.com/KhronosGroup/glTF-Sample-Assets
- Poly Haven CC0 assets: https://polyhaven.com/

License note: imported sample assets must keep their own license and attribution metadata. CC0 assets are easiest for demos. Creative Commons assets with attribution requirements are usable only when attribution is tracked and shipped correctly. Marketplace assets such as Sketchfab downloads must be reviewed per asset and should not be assumed safe just because a preview is visible.

## Localization

Project decision:

- use gettext-style PO files as the project localization source format
- keep runtime lookup behind a small engine localization service
- do not require Qt runtime libraries or Qt-specific QM files for localization

gettext PO files are toolkit-neutral, text-based, diff-friendly, and widely supported by translation tools. They support translator comments, contexts, plural forms, and normal source extraction workflows. This fits the project better than adopting Qt TS/QM as the runtime format only to get the Qt Linguist tools.

Qt Linguist remains a useful reference point for workflow quality. Its `lupdate`/`lrelease` flow and translator UI show what good tooling looks like. The project should not depend on Qt just for localized strings unless there is a stronger reason later. If translators strongly prefer Qt Linguist, a converter path can be evaluated, but the project source of truth should stay neutral.

Recommended structure:

```text
locale/
  de/LC_MESSAGES/demo.po
  en/LC_MESSAGES/demo.po
```

Runtime shape:

- UI code asks for localized strings through a small function such as `tr("ui.sidebar.help")` or a context-aware equivalent.
- The localization service owns current language, fallback language, catalog lookup, missing-key logging, and formatting.
- Visible user-facing strings should gradually move out of demo construction code and into catalogs.
- The first runtime may load PO directly for simplicity. A later build step can compile PO into MO or a compact project-specific catalog if startup or lookup cost matters.

Useful references:

- GNU gettext manual: https://www.gnu.org/software/gettext/manual/gettext.html
- Qt Linguist manager workflow: https://doc.qt.io/qt-6/linguist-manager.html
- Qt `lrelease` and QM files: https://doc.qt.io/qt-6/linguist-lrelease.html
- Qt licensing overview: https://doc.qt.io/qt-6/licensing.html

## Planned Engine Boundary

The asset and localization layer should become a reusable service boundary, not demo-only helper code:

- `vulkan.assets` or a similarly neutral package owns decoded image data, model data, and asset ids.
- `vulkan.localization` or a neutral engine package owns string catalogs and lookup.
- Renderer modules receive decoded pixels, mesh buffers, material data, and text strings; they do not parse PNG, glTF, PO, or editor-specific files directly.
- Demo code chooses asset ids and localized text ids, then lets the reusable services resolve them.
