# Audio Architecture

This document describes the planned audio layer for the engine prototype. A first backend-neutral runtime now exists for audio bus state, typed audio events, an event queue, and settings-to-bus volume mapping. SDL playback stream ownership also exists as a small lifecycle wrapper. The first mixer primitive can clear and mix interleaved floating-point sample blocks with bus gain and sample clamping. Decoded clips and active voice primitives exist for non-looped and looped playback into mixer buffers. `playClip` and `stopAll` events can now create and stop voices from registered clips. The runtime also registers a tiny synthetic `ui/click` clip until real UI sound assets exist, and the renderer queues it when retained buttons activate. The renderer pumps active voices or short silence blocks into an SDL audio stream when audio output is available, keeping the stream warm without a large latency queue. Queued idle silence is discarded before a new short UI sound so the sound does not sit behind buffered silence. File loading, voice limits, and streamed music are still planned and should be added behind the same reusable audio service instead of embedding playback directly in demo UI or renderer code.

## Goals

The audio layer should provide predictable playback for game and UI sound without tying gameplay code to a concrete backend.

Core goals:

- keep audio device ownership separate from renderer ownership
- route gameplay and UI intent through audio events
- mix short sound effects, UI feedback sounds, ambient loops, and music streams through a small bus model
- expose master, music, and effects volume controls that match the existing demo settings
- avoid blocking the frame loop on file loading or decode work
- keep backend-specific details behind a compact D API

## Usual Engine Split

A typical game audio architecture has these layers:

- `AudioDevice`: owns the backend device/stream, requested playback format, actual playback format, pause/resume, queueing, and shutdown. Basic SDL stream output exists.
- `AudioMixer`: combines active voices into the device callback buffer. Basic interleaved float-buffer mixing exists; active voice ownership is planned.
- `AudioBus`: groups voices by purpose, currently master, music, effects, and UI. Basic bus state exists.
- `AudioClip`: decoded or preloaded short sound data for low-latency effects. Basic in-memory interleaved float clips exist; loading from assets is planned.
- `AudioStream`: longer decoded-on-demand source for music or ambience. Planned.
- `AudioVoice`: one active playback instance with gain, pan, pitch, loop state, and remaining lifetime. Basic gain, bus, cursor, active, and loop state exist; `AudioSystem` can schedule voices from `playClip` events. Pan/pitch and voice-limit policy are planned.
- `AudioEvent`: typed request from gameplay or UI code, such as play sound, stop sound, set bus volume, fade music, or trigger a transition. Basic event types exist.
- `AudioSystem`: frame-facing owner that receives events, updates fades and voice state, and feeds the mixer. The first implementation owns the event queue, bus-volume state, clip registry, and active voices; the renderer currently pumps mixed blocks into an SDL audio stream.

The important boundary is that game and UI code should emit intent, not push samples. The audio system owns playback policy, voice limits, fades, and backend details.

## Event Flow

The expected event flow is:

1. Gameplay, UI, or demo code emits an `AudioEvent`.
2. The main thread queues the event in the `AudioSystem`.
3. The audio system resolves bus routing and playback parameters. Currently this applies bus-volume state, records fade targets, and maps `playClip` events to registered clips and active voices.
4. The mixer owns active voices and produces interleaved samples for the device callback. The current mixer can clear output buffers, mix already-decoded interleaved float blocks with bus gain, and render simple clip voices scheduled by `AudioSystem`.
5. The backend writes mixed samples to the platform audio device. The renderer currently opens an SDL audio stream, resumes it when possible, and keeps a small queue filled with mixed UI/event audio or silence so the stream does not need to restart after idle periods. When a new one-shot UI sound arrives after idle time, the renderer clears the known silence queue and immediately pumps the mixed sound block.

Audio events should stay small and serializable enough to log, test, or replay. Examples include `playUiClick`, `playEffect(assetId)`, `startMusic(trackId)`, `fadeBus(busId, targetVolume, duration)`, and `stopAll(busId)`. The current UI click path is intentionally synthetic: it proves the event-to-voice path without depending on a package asset or SDL callback yet.

## Music And Ambience

Music should be modeled as streamed or chunk-decoded audio, not as a fully preloaded effect. The engine should support:

- one current music track plus one optional fading-out track
- loop points or whole-track looping
- fade in, fade out, and crossfade
- pause, resume, and stop
- separate music bus volume

Ambient loops can use the same stream/voice model, but they normally route to an ambience or effects bus depending on how broad the first implementation should be.

## Backend Direction

SDL audio is the most natural first backend because SDL already owns window and input integration in this repository. The backend should be swappable later if needed, but the first useful implementation can be:

- SDL audio stream output first; a callback can be added later if frame-driven queueing is not enough
- engine-owned mixer with `float` sample processing. Basic block mixing exists.
- short clips decoded into memory. The in-memory clip representation exists; decoding and asset lookup are planned.
- simple streaming abstraction for music
- backend-independent event and bus types

The first version does not need positional 3D audio. Stereo pan, per-bus volume, per-voice gain, and music fades are enough to exercise the architecture. The current `AudioDevice` wrapper requests stereo 48 kHz floating-point playback by default and stores the actual SDL format after opening.

## Settings

The existing demo settings already contain:

- `masterVolume`
- `musicVolume`
- `effectsVolume`

These map to the current buses through `AudioSystem.applyVolumeSettings`. `masterVolume` controls the master bus, `musicVolume` controls the music bus, and `effectsVolume` controls both effects and UI buses until the settings model gains a dedicated UI volume. The renderer owns the first `AudioSystem` instance, applies loaded settings during startup, and re-applies the settings dialog values through the audio event queue on Apply or Save.

Audio sliders in the Settings window also trigger a small preview path when the pointer gesture is committed. While a slider is dragged, the demo UI updates only the settings draft and the visible text; on release, the renderer applies those draft volumes to the live audio buses and queues the synthetic `ui/click` clip on the preview bus for the changed setting. This keeps the preview audible without persisting settings before Apply or Save and avoids click cascades during continuous drag. A later audio demo should add real effect assets, a dedicated music preview, and a separate UI volume control if needed.

## Open Questions

- Which audio file formats should the first backend support?
- Should decoding be implemented through SDL-compatible helpers, a small D dependency, or a custom minimal loader?
- Should the settings model gain a separate UI volume now that the engine has a distinct `ui` bus?
- How should audio assets be named and located before a real asset pipeline exists?
- What voice limit and stealing policy should effects use?
