#!/usr/bin/env dub
/** $purposeofFile
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018
 * License: CC-BY-NC-SA 4.0
 */
/+ dub.sdl:
name "release-timetag"
dependency "va_toolbox" version="~>0.4.0"
+/
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