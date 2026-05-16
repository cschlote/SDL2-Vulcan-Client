# Audio Architecture

This document describes the planned audio layer for the engine prototype. No dedicated audio runtime exists yet; the current settings model already reserves audio configuration values, and the next implementation should add a reusable audio service instead of embedding sound playback directly in demo UI or renderer code.

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

- `AudioDevice`: owns the backend device, callback, sample format, channel count, and buffer size.
- `AudioMixer`: combines active voices into the device callback buffer.
- `AudioBus`: groups voices by purpose, usually master, music, effects, ambience, and UI.
- `AudioClip`: decoded or preloaded short sound data for low-latency effects.
- `AudioStream`: longer decoded-on-demand source for music or ambience.
- `AudioVoice`: one active playback instance with gain, pan, pitch, loop state, and remaining lifetime.
- `AudioEvent`: typed request from gameplay or UI code, such as play sound, stop sound, set bus volume, fade music, or trigger a transition.
- `AudioSystem`: frame-facing owner that receives events, updates fades and voice state, and feeds the mixer.

The important boundary is that game and UI code should emit intent, not push samples. The audio system owns playback policy, voice limits, fades, and backend details.

## Event Flow

The expected event flow is:

1. Gameplay, UI, or demo code emits an `AudioEvent`.
2. The main thread queues the event in the `AudioSystem`.
3. The audio system resolves asset IDs, bus routing, and playback parameters.
4. The mixer owns active voices and produces interleaved samples for the device callback.
5. The backend writes mixed samples to the platform audio device.

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
- engine-owned mixer with `float` sample processing
- short clips decoded into memory
- simple streaming abstraction for music
- backend-independent event and bus types

The first version does not need positional 3D audio. Stereo pan, per-bus volume, per-voice gain, and music fades are enough to exercise the architecture.

## Settings

The existing demo settings already contain:

- `masterVolume`
- `musicVolume`
- `effectsVolume`

These should map to audio buses when the audio system is added. The settings dialog can later expose those values through sliders and apply them by emitting bus-volume events instead of writing directly into audio internals.

## Open Questions

- Which audio file formats should the first backend support?
- Should decoding be implemented through SDL-compatible helpers, a small D dependency, or a custom minimal loader?
- Should UI sounds use a separate `ui` bus or share the effects bus at first?
- How should audio assets be named and located before a real asset pipeline exists?
- What voice limit and stealing policy should effects use?
