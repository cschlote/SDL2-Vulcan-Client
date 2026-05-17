# Audio Architecture

This document describes the planned audio layer for the engine prototype. A first backend-neutral runtime now exists for audio bus state, typed audio events, an event queue, and settings-to-bus volume mapping. SDL playback device ownership also exists as a small lifecycle wrapper. The first mixer primitive can clear and mix interleaved floating-point sample blocks with bus gain and sample clamping. Clips, active voices, and streamed music are still planned and should be added behind the same reusable audio service instead of embedding playback directly in demo UI or renderer code.

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

- `AudioDevice`: owns the backend device, requested playback format, actual playback format, pause/resume, and shutdown. Basic SDL owner exists; callback and stream binding are planned.
- `AudioMixer`: combines active voices into the device callback buffer. Basic interleaved float-buffer mixing exists; active voice ownership is planned.
- `AudioBus`: groups voices by purpose, currently master, music, effects, and UI. Basic bus state exists.
- `AudioClip`: decoded or preloaded short sound data for low-latency effects. Planned.
- `AudioStream`: longer decoded-on-demand source for music or ambience. Planned.
- `AudioVoice`: one active playback instance with gain, pan, pitch, loop state, and remaining lifetime. Planned.
- `AudioEvent`: typed request from gameplay or UI code, such as play sound, stop sound, set bus volume, fade music, or trigger a transition. Basic event types exist.
- `AudioSystem`: frame-facing owner that receives events, updates fades and voice state, and feeds the mixer. The first implementation owns the event queue and bus-volume state; mixer/device integration is planned.

The important boundary is that game and UI code should emit intent, not push samples. The audio system owns playback policy, voice limits, fades, and backend details.

## Event Flow

The expected event flow is:

1. Gameplay, UI, or demo code emits an `AudioEvent`.
2. The main thread queues the event in the `AudioSystem`.
3. The audio system resolves bus routing and playback parameters. Currently this applies bus-volume state and records fade targets.
4. The mixer owns active voices and produces interleaved samples for the device callback. The current mixer can clear output buffers and mix already-decoded interleaved float blocks with bus gain; voice scheduling is planned.
5. The backend writes mixed samples to the platform audio device. The SDL device owner exists, but is not opened automatically until the mixer/service integration is added.

Audio events should stay small and serializable enough to log, test, or replay. Examples include `playUiClick`, `playEffect(assetId)`, `startMusic(trackId)`, `fadeBus(busId, targetVolume, duration)`, and `stopAll(busId)`.

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

- SDL audio device callback
- engine-owned mixer with `float` sample processing. Basic block mixing exists.
- short clips decoded into memory
- simple streaming abstraction for music
- backend-independent event and bus types

The first version does not need positional 3D audio. Stereo pan, per-bus volume, per-voice gain, and music fades are enough to exercise the architecture. The current `AudioDevice` wrapper requests stereo 48 kHz floating-point playback by default and stores the actual SDL format after opening.

## Settings

The existing demo settings already contain:

- `masterVolume`
- `musicVolume`
- `effectsVolume`

These map to the current buses through `AudioSystem.applyVolumeSettings`. `masterVolume` controls the master bus, `musicVolume` controls the music bus, and `effectsVolume` controls both effects and UI buses until the settings model gains a dedicated UI volume. The renderer owns the first `AudioSystem` instance, applies loaded settings during startup, and re-applies the settings dialog values through the audio event queue on Apply or Save. This is still silent until the SDL device and mixer are added.

## Open Questions

- Which audio file formats should the first backend support?
- Should decoding be implemented through SDL-compatible helpers, a small D dependency, or a custom minimal loader?
- Should the settings model gain a separate UI volume now that the engine has a distinct `ui` bus?
- How should audio assets be named and located before a real asset pipeline exists?
- What voice limit and stealing policy should effects use?
