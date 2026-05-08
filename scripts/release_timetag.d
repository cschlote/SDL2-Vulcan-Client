module scripts.release_timetag;

import std.stdio : writefln;

import va_toolbox.timetags : getTimeTagString;

void main()
{
    writefln("Release timetag: %s", getTimeTagString());
}