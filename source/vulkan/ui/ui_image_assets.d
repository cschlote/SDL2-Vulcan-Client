/** Small registry for renderer-facing UI image asset regions.
 *
 * The first implementation maps asset ids to UV rectangles inside a single
 * renderer-owned UI image texture. A later file-backed asset pipeline can keep
 * the same id lookup while replacing the generated texture.
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.ui.ui_image_assets;

import std.conv : to;
import std.exception : enforce;
import std.file : read;

/** Renderer-resolved image metadata for one UI asset id. */
struct UiImageAsset
{
    /** Stable asset id used by retained widgets. */
    string id;
    /** UV rectangle inside the renderer-bound UI image texture, ordered u0, v0, u1, v1. */
    float[4] uvRect;
}

/** Decoded RGBA bitmap used before it is packed into a renderer atlas. */
struct UiImageBitmap
{
    /** Width in pixels. */
    uint width;
    /** Height in pixels. */
    uint height;
    /** Interleaved RGBA8 pixels, row-major. */
    ubyte[] rgba;

    /** Returns true when this bitmap has no usable pixel payload. */
    bool empty() const
    {
        return width == 0 || height == 0 || rgba.length == 0;
    }
}

/** Maps retained UI image asset ids to renderer atlas regions. */
final class UiImageAssetRegistry
{
    private UiImageAsset[string] assets;

    /** Registers or replaces one texture-region mapping. */
    void registerAsset(string id, float[4] uvRect)
    {
        if (id.length == 0)
            return;

        assets[id] = UiImageAsset(id, uvRect);
    }

    /** Returns true and fills `asset` when `id` is registered. */
    bool resolve(string id, out UiImageAsset asset) const
    {
        auto found = id in assets;
        if (found is null)
            return false;

        asset = *found;
        return true;
    }

    /** Removes all registered asset mappings. */
    void clear()
    {
        assets.clear();
    }

    /** Number of registered asset ids. */
    size_t length() const
    {
        return assets.length;
    }
}

/** Loads a simple PPM image from disk and converts it to RGBA8.
 *
 * This intentionally small loader supports P3 and P6 PPM files. It gives the
 * demo a file-backed UI image path without introducing the final asset package
 * or PNG/JPEG dependency yet.
 */
UiImageBitmap loadPpmUiImage(string path)
{
    return decodePpmUiImage(cast(const(ubyte)[])read(path), path);
}

/** Decodes P3/P6 PPM bytes into RGBA8 pixel data. */
UiImageBitmap decodePpmUiImage(const(ubyte)[] data, string sourceName = "<memory>")
{
    PpmScanner scanner;
    scanner.data = data;

    const magic = scanner.nextToken(sourceName);
    enforce(magic == "P3" || magic == "P6", "Unsupported PPM magic in " ~ sourceName);
    const width = scanner.nextToken(sourceName).to!uint;
    const height = scanner.nextToken(sourceName).to!uint;
    const maxValue = scanner.nextToken(sourceName).to!uint;
    enforce(width > 0 && height > 0, "PPM image has invalid dimensions in " ~ sourceName);
    enforce(maxValue > 0 && maxValue <= 255, "PPM image uses unsupported max value in " ~ sourceName);

    UiImageBitmap bitmap;
    bitmap.width = width;
    bitmap.height = height;
    bitmap.rgba.length = cast(size_t)width * height * 4;

    if (magic == "P3")
    {
        foreach (pixel; 0 .. cast(size_t)width * height)
        {
            bitmap.rgba[pixel * 4 + 0] = scalePpmSample(scanner.nextToken(sourceName).to!uint, maxValue);
            bitmap.rgba[pixel * 4 + 1] = scalePpmSample(scanner.nextToken(sourceName).to!uint, maxValue);
            bitmap.rgba[pixel * 4 + 2] = scalePpmSample(scanner.nextToken(sourceName).to!uint, maxValue);
            bitmap.rgba[pixel * 4 + 3] = 255;
        }
        return bitmap;
    }

    scanner.consumeSingleWhitespace(sourceName);
    const requiredBytes = cast(size_t)width * height * 3;
    enforce(scanner.position + requiredBytes <= data.length, "PPM image is truncated in " ~ sourceName);
    foreach (pixel; 0 .. cast(size_t)width * height)
    {
        bitmap.rgba[pixel * 4 + 0] = scalePpmSample(data[scanner.position + pixel * 3 + 0], maxValue);
        bitmap.rgba[pixel * 4 + 1] = scalePpmSample(data[scanner.position + pixel * 3 + 1], maxValue);
        bitmap.rgba[pixel * 4 + 2] = scalePpmSample(data[scanner.position + pixel * 3 + 2], maxValue);
        bitmap.rgba[pixel * 4 + 3] = 255;
    }
    return bitmap;
}

private ubyte scalePpmSample(uint value, uint maxValue)
{
    enforce(value <= maxValue, "PPM sample exceeds max value.");
    return cast(ubyte)((value * 255 + maxValue / 2) / maxValue);
}

private struct PpmScanner
{
    const(ubyte)[] data;
    size_t position;

    void skipWhitespaceAndComments()
    {
        while (position < data.length)
        {
            if (isPpmWhitespace(data[position]))
            {
                ++position;
                continue;
            }
            if (data[position] == '#')
            {
                while (position < data.length && data[position] != '\n' && data[position] != '\r')
                    ++position;
                continue;
            }
            break;
        }
    }

    string nextToken(string sourceName)
    {
        skipWhitespaceAndComments();
        enforce(position < data.length, "Unexpected end of PPM data in " ~ sourceName);
        const start = position;
        while (position < data.length && !isPpmWhitespace(data[position]) && data[position] != '#')
            ++position;
        enforce(position > start, "Expected PPM token in " ~ sourceName);
        return cast(string)data[start .. position];
    }

    void consumeSingleWhitespace(string sourceName)
    {
        enforce(position < data.length && isPpmWhitespace(data[position]), "Expected PPM raster separator in " ~ sourceName);
        ++position;
    }
}

private bool isPpmWhitespace(ubyte value)
{
    return value == ' ' || value == '\t' || value == '\n' || value == '\r' || value == '\f';
}

@("UiImageAssetRegistry resolves registered atlas regions")
unittest
{
    auto registry = new UiImageAssetRegistry();
    registry.registerAsset("sidebar/help", [0.0f, 0.0f, 0.25f, 0.25f]);

    UiImageAsset asset;
    assert(registry.resolve("sidebar/help", asset));
    assert(asset.id == "sidebar/help");
    assert(asset.uvRect == [0.0f, 0.0f, 0.25f, 0.25f]);
    assert(!registry.resolve("missing", asset));
    assert(registry.length == 1);
}

@("decodePpmUiImage decodes ASCII PPM into RGBA pixels")
unittest
{
    const data = cast(const(ubyte)[])"P3\n# demo\n2 1\n255\n255 0 0  0 64 255\n";
    auto bitmap = decodePpmUiImage(data);
    assert(bitmap.width == 2);
    assert(bitmap.height == 1);
    assert(bitmap.rgba == [255, 0, 0, 255, 0, 64, 255, 255]);
}
