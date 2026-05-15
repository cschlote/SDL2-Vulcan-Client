/** Demo settings persistence for the SDL2 Vulkan application.
 *
 * Stores the user-facing demo configuration in a small INI file under
 * ~/.config/sdl2-vulcan-demo/config so the application can restore its
 * startup state without external dependencies.
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module demo_settings;

import std.algorithm : canFind, splitter;
import std.array : appender;
import std.conv : ConvException, to;
import std.exception : collectException;
import std.file : exists, mkdirRecurse, readText, write;
import std.path : buildPath, dirName, expandTilde;
import std.string : indexOf, strip, toLower;

/** Display-related demo settings. */
struct DemoDisplaySettings
{
    string windowMode = "windowed";
    uint windowWidth = 1280;
    uint windowHeight = 720;
    bool fullscreen;
    bool vsync = true;
    float scale = 1.0f;
}

/** Input-related demo settings. */
struct DemoControlsSettings
{
    float mouseSensitivity = 1.0f;
    float cameraSpeed = 1.0f;
    bool invertMouseY;
}

/** Demo flow and startup settings. */
struct DemoGameplaySettings
{
    string startupShape = "DODECAHEDRON";
    string startupRenderMode = "litTextured";
    bool showHints = true;
}

/** Audio-related demo settings. */
struct DemoAudioSettings
{
    float masterVolume = 1.0f;
    float musicVolume = 0.8f;
    float effectsVolume = 0.8f;
}

/** UI-related demo settings. */
struct DemoUiSettings
{
    float fontScale = 1.0f;
    string theme = "midnight";
    bool compactWindows;
}

/** Full demo settings bundle. */
struct DemoSettings
{
    DemoDisplaySettings display;
    DemoControlsSettings controls;
    DemoGameplaySettings gameplay;
    DemoAudioSettings audio;
    DemoUiSettings ui;
}

/** Returns the default configuration file path for the demo. */
string demoSettingsPath()
{
    return expandTilde("~/.config/sdl2-vulcan-demo/config");
}

/** Loads the demo settings from the INI file if it exists. */
DemoSettings loadDemoSettings(string path = demoSettingsPath())
{
    DemoSettings settings = DemoSettings.init;
    settings.display = DemoDisplaySettings.init;
    settings.controls = DemoControlsSettings.init;
    settings.gameplay = DemoGameplaySettings.init;
    settings.audio = DemoAudioSettings.init;
    settings.ui = DemoUiSettings.init;

    if (!exists(path))
        return settings;

    string currentSection;
    foreach (rawLine; readText(path).splitter('\n'))
    {
        const line = rawLine.strip;
        if (line.length == 0 || line[0] == '#' || line[0] == ';')
            continue;

        if (line.length >= 2 && line[0] == '[' && line[$ - 1] == ']')
        {
            currentSection = line[1 .. $ - 1].strip.idup;
            continue;
        }

        const equalsIndex = indexOf(line, '=');
        if (equalsIndex <= 0)
            continue;

        const key = line[0 .. equalsIndex].strip;
        const value = line[equalsIndex + 1 .. $].strip;
        applySetting(settings, currentSection, key, value);
    }

    return settings;
}

/** Saves the demo settings to the INI file. */
void saveDemoSettings(ref const DemoSettings settings, string path = demoSettingsPath())
{
    mkdirRecurse(dirName(path));
    auto output = appender!string();

    output.put("[display]\n");
    output.put(formatKeyValue("windowMode", settings.display.windowMode));
    output.put(formatKeyValue("windowWidth", settings.display.windowWidth));
    output.put(formatKeyValue("windowHeight", settings.display.windowHeight));
    output.put(formatKeyValue("fullscreen", settings.display.fullscreen));
    output.put(formatKeyValue("vsync", settings.display.vsync));
    output.put(formatKeyValue("scale", settings.display.scale));
    output.put('\n');

    output.put("[controls]\n");
    output.put(formatKeyValue("mouseSensitivity", settings.controls.mouseSensitivity));
    output.put(formatKeyValue("cameraSpeed", settings.controls.cameraSpeed));
    output.put(formatKeyValue("invertMouseY", settings.controls.invertMouseY));
    output.put('\n');

    output.put("[gameplay]\n");
    output.put(formatKeyValue("startupShape", settings.gameplay.startupShape));
    output.put(formatKeyValue("startupRenderMode", settings.gameplay.startupRenderMode));
    output.put(formatKeyValue("showHints", settings.gameplay.showHints));
    output.put('\n');

    output.put("[audio]\n");
    output.put(formatKeyValue("masterVolume", settings.audio.masterVolume));
    output.put(formatKeyValue("musicVolume", settings.audio.musicVolume));
    output.put(formatKeyValue("effectsVolume", settings.audio.effectsVolume));
    output.put('\n');

    output.put("[ui]\n");
    output.put(formatKeyValue("fontScale", settings.ui.fontScale));
    output.put(formatKeyValue("theme", settings.ui.theme));
    output.put(formatKeyValue("compactWindows", settings.ui.compactWindows));

    write(path, output.data);
}

private void applySetting(ref DemoSettings settings, string section, string key, string value)
{
    switch (section)
    {
        case "display":
            if (key == "windowMode")
                settings.display.windowMode = value;
            else if (key == "windowWidth")
                settings.display.windowWidth = parseValue!uint(value, settings.display.windowWidth);
            else if (key == "windowHeight")
                settings.display.windowHeight = parseValue!uint(value, settings.display.windowHeight);
            else if (key == "fullscreen")
                settings.display.fullscreen = parseBool(value, settings.display.fullscreen);
            else if (key == "vsync")
                settings.display.vsync = parseBool(value, settings.display.vsync);
            else if (key == "scale")
                settings.display.scale = parseValue!float(value, settings.display.scale);
            break;
        case "controls":
            if (key == "mouseSensitivity")
                settings.controls.mouseSensitivity = parseValue!float(value, settings.controls.mouseSensitivity);
            else if (key == "cameraSpeed")
                settings.controls.cameraSpeed = parseValue!float(value, settings.controls.cameraSpeed);
            else if (key == "invertMouseY")
                settings.controls.invertMouseY = parseBool(value, settings.controls.invertMouseY);
            break;
        case "gameplay":
            if (key == "startupShape")
                settings.gameplay.startupShape = value;
            else if (key == "startupRenderMode")
                settings.gameplay.startupRenderMode = value;
            else if (key == "showHints")
                settings.gameplay.showHints = parseBool(value, settings.gameplay.showHints);
            break;
        case "audio":
            if (key == "masterVolume")
                settings.audio.masterVolume = parseValue!float(value, settings.audio.masterVolume);
            else if (key == "musicVolume")
                settings.audio.musicVolume = parseValue!float(value, settings.audio.musicVolume);
            else if (key == "effectsVolume")
                settings.audio.effectsVolume = parseValue!float(value, settings.audio.effectsVolume);
            break;
        case "ui":
            if (key == "fontScale")
                settings.ui.fontScale = parseValue!float(value, settings.ui.fontScale);
            else if (key == "theme")
                settings.ui.theme = value;
            else if (key == "compactWindows")
                settings.ui.compactWindows = parseBool(value, settings.ui.compactWindows);
            break;
        default:
            break;
    }
}

private string formatKeyValue(T)(string key, T value)
{
    return key ~ "=" ~ formatValue(value) ~ "\n";
}

private string formatValue(bool value)
{
    return value ? "true" : "false";
}

private string formatValue(T)(T value)
{
    static if (is(T == bool))
    {
        return formatValue(value);
    }
    else static if (is(T == string))
    {
        return value;
    }
    else
    {
        return to!string(value);
    }
}

private bool parseBool(string value, bool fallback)
{
    immutable normalized = toLower(value.strip);
    if (normalized.canFind("true") || normalized == "1" || normalized == "yes" || normalized == "on")
        return true;
    if (normalized.canFind("false") || normalized == "0" || normalized == "no" || normalized == "off")
        return false;
    return fallback;
}

private T parseValue(T)(string value, T fallback)
{
    try
    {
        return to!T(value);
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
