/** Clip and voice playback primitives for the engine audio layer.
 *
 * This module models decoded short clips and active playback voices without
 * loading files or touching SDL. It can render voices into an `AudioMixBuffer`
 * so later event handling can turn `playClip` requests into real mixer input.
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.audio.audio_voice;

import std.algorithm : min;

import vulkan.audio.audio_mixer : AudioMixBuffer;
import vulkan.audio.audio_system : AudioBusId, AudioSystem;

/** Decoded interleaved floating-point audio data. */
struct AudioClip
{
    /** Symbolic asset id used by audio events. */
    string id;
    /** Interleaved sample data in normalized float format. */
    float[] samples;
    /** Sample rate in Hz. */
    int frequency = 48_000;
    /** Interleaved channel count. */
    int channels = 2;

    /** Creates a clip from interleaved normalized float samples. */
    static AudioClip fromInterleaved(string id, const(float)[] samples, int channels = 2, int frequency = 48_000)
    {
        AudioClip clip;
        clip.id = id;
        clip.samples = samples.dup;
        clip.channels = channels > 0 ? channels : 2;
        clip.frequency = frequency > 0 ? frequency : 48_000;
        return clip;
    }

    /** Returns true when the clip has usable sample data and channel layout. */
    bool isValid() const
    {
        return channels > 0 && samples.length >= cast(size_t)channels;
    }

    /** Returns the number of complete frames in this clip. */
    size_t frameCount() const
    {
        return channels > 0 ? samples.length / cast(size_t)channels : 0;
    }
}

/** One active playback instance of an `AudioClip`. */
struct AudioVoice
{
    /** Source clip to read from. */
    AudioClip clip;
    /** Target bus for bus gain. */
    AudioBusId bus = AudioBusId.effects;
    /** Per-voice gain before bus gain. */
    float gain = 1.0f;
    /** Whether playback wraps to the clip start. */
    bool loop;
    /** Current playback frame inside `clip`. */
    size_t cursorFrame;
    /** False after a non-looping voice reaches the end. */
    bool active = true;

    /** Creates a voice for a decoded clip. */
    static AudioVoice play(AudioClip clip, AudioBusId bus = AudioBusId.effects, float gain = 1.0f, bool loop = false)
    {
        AudioVoice voice;
        voice.clip = clip;
        voice.bus = bus;
        voice.gain = clampGain(gain);
        voice.loop = loop;
        voice.cursorFrame = 0;
        voice.active = clip.isValid();
        return voice;
    }

    /** Stops the voice without clearing its cursor. */
    void stop()
    {
        active = false;
    }
}

/** Mixes one active voice into an output buffer.
 *
 * Returns the number of output frames touched. Resampling is intentionally not
 * implemented yet; callers should feed clips matching the mixer/device format.
 */
size_t mixVoice(ref AudioMixBuffer output, ref AudioVoice voice, const(AudioSystem) audioSystem)
{
    if (!voice.active || !voice.clip.isValid() || output.samples.length == 0 || output.channels <= 0)
        return 0;

    const clipFrames = voice.clip.frameCount();
    if (clipFrames == 0)
    {
        voice.active = false;
        return 0;
    }

    const outputFrames = output.frameCount();
    size_t touchedFrames;
    const busGain = audioSystem is null ? 1.0f : audioSystem.effectiveBusVolume(voice.bus);
    const finalGain = clampGain(voice.gain) * busGain;

    foreach (frame; 0 .. outputFrames)
    {
        if (voice.cursorFrame >= clipFrames)
        {
            if (!voice.loop)
            {
                voice.active = false;
                break;
            }
            voice.cursorFrame = 0;
        }

        mixVoiceFrame(output, frame, voice.clip, voice.cursorFrame, finalGain);
        ++voice.cursorFrame;
        ++touchedFrames;
    }

    if (!voice.loop && voice.cursorFrame >= clipFrames)
        voice.active = false;

    return touchedFrames;
}

private void mixVoiceFrame(ref AudioMixBuffer output, size_t outputFrame, ref const(AudioClip) clip, size_t clipFrame, float gain)
{
    const outputChannels = cast(size_t)output.channels;
    const clipChannels = cast(size_t)clip.channels;
    const outputBase = outputFrame * outputChannels;
    const clipBase = clipFrame * clipChannels;

    foreach (channel; 0 .. outputChannels)
    {
        const sourceChannel = clipChannels == 1 ? 0 : min(channel, clipChannels - 1);
        const source = clip.samples[clipBase + sourceChannel];
        output.samples[outputBase + channel] = clampSample(output.samples[outputBase + channel] + source * gain);
    }
}

private float clampGain(float value)
{
    if (value < 0.0f)
        return 0.0f;
    if (value > 1.0f)
        return 1.0f;
    return value;
}

private float clampSample(float value)
{
    if (value < -1.0f)
        return -1.0f;
    if (value > 1.0f)
        return 1.0f;
    return value;
}

version (unittest)
{
    import vulkan.audio.audio_mixer : AudioMixer;

    private void assertNear(float actual, float expected)
    {
        const delta = actual > expected ? actual - expected : expected - actual;
        assert(delta < 0.0001f);
    }
}

unittest
{
    const samples = [0.25f, -0.25f, 0.5f, -0.5f];
    auto clip = AudioClip.fromInterleaved("ui/click", samples, 2, 48_000);

    assert(clip.isValid());
    assert(clip.frameCount() == 2);
    assert(clip.samples.length == samples.length);
}

unittest
{
    auto audio = new AudioSystem();
    audio.applyVolumeSettings(0.5f, 1.0f, 0.5f);
    audio.processEvents();

    auto mixer = new AudioMixer();
    auto buffer = mixer.createBuffer(4);
    auto clip = AudioClip.fromInterleaved("effect/tick", [0.8f, -0.8f, 0.4f, -0.4f], 2);
    auto voice = AudioVoice.play(clip, AudioBusId.effects, 0.5f);

    assert(mixVoice(buffer, voice, audio) == 2);
    assert(!voice.active);
    assert(voice.cursorFrame == 2);
    assertNear(buffer.samples[0], 0.1f);
    assertNear(buffer.samples[1], -0.1f);
    assertNear(buffer.samples[2], 0.05f);
    assertNear(buffer.samples[3], -0.05f);
    assertNear(buffer.samples[4], 0.0f);
}

unittest
{
    auto mixer = new AudioMixer();
    auto buffer = mixer.createBuffer(3);
    auto clip = AudioClip.fromInterleaved("ui/pulse", [0.5f, -0.5f], 2);
    auto voice = AudioVoice.play(clip, AudioBusId.ui, 1.0f, true);

    assert(mixVoice(buffer, voice, null) == 3);
    assert(voice.active);
    assert(voice.cursorFrame == 1);
    assertNear(buffer.samples[0], 0.5f);
    assertNear(buffer.samples[1], -0.5f);
    assertNear(buffer.samples[2], 0.5f);
    assertNear(buffer.samples[3], -0.5f);
    assertNear(buffer.samples[4], 0.5f);
    assertNear(buffer.samples[5], -0.5f);
}
