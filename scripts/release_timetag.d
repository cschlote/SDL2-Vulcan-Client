#!/usr/bin/env dub
/+ dub.sdl:
name "release-timetag"
dependency "va_toolbox" version="~>0.4.0"
+/
/** Prints the release timetag and matching Git tag.
 *
 * Uses the shared time-tag helper to derive the current release version and
 * prints the Git tag prefix expected by the release workflow. See README.md
 * and CHANGELOG.md for the surrounding release notes.
 *
 * See_Also:
 *   README.md
 *   CHANGELOG.md
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module scripts.release_timetag;

import std.stdio : writefln;

import va_toolbox.timetags : getTimeTagString;

enum gitTagPrefix = "v";

/** Prints the release timetag together with the Git tag that should be used. */
void main()
{
    const timeTag = getTimeTagString();
    writefln("Release timetag: %s", timeTag);
    writefln("Git tag: %s%s", gitTagPrefix, timeTag);
}