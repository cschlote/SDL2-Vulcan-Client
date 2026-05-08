#!/usr/bin/env dub
/+ dub.sdl:
name "release-timetag"
dependency "va_toolbox" version="~>0.4.0"
+/
module scripts.release_timetag;

import std.stdio : writefln;

import va_toolbox.timetags : getTimeTagString;

void main()
{
    writefln("Release timetag: %s", getTimeTagString());
}