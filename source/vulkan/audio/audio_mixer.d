/** Float sample mixer primitives for the engine audio layer.
 *
 * The first mixer operates on interleaved floating-point sample buffers and
 * applies bus gain. It does not own clips or voices yet; those later systems
 * can feed blocks into this module without changing the backend-facing format.
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.audio.audio_mixer;

import std.algorithm : min;

import vulkan.audio.audio_system : AudioBusId, AudioSystem;

/** Runtime output format for interleaved mixer buffers. */
struct AudioMixFormat
{
    /** Sample rate in Hz. */
    int frequency = 48_000;
    /** Interleaved channel count. */
    int channels = 2;

    /** Returns a sanitized copy usable by buffer sizing code. */
    AudioMixFormat normalized() const
    {
        AudioMixFormat format;
        format.frequency = frequency > 0 ? frequency : 48_000;
        format.channels = channels > 0 ? channels : 2;
        return format;
    }
}

/** A small interleaved float output buffer owned by the mixer caller. */
struct AudioMixBuffer
{
    /** Interleaved samples in channel-major frame order. */
    float[] samples;
    /** Number of channels represented in `samples`. */
    int channels = 2;

    /** Resizes the buffer for the requested frame and channel count. */
    void resize(size_t frames, int channels)
    {
        this.channels = channels > 0 ? channels : 2;
        samples.length = frames * cast(size_t)this.channels;
    }

    /** Returns the number of complete frames in the buffer. */
    size_t frameCount() const
    {
        return channels > 0 ? samples.length / cast(size_t)channels : 0;
    }

    /** Fills the buffer with silence. */
    void clear()
    {
        samples[] = 0.0f;
    }
}

/** Stateless float mixer facade with retained format metadata. */
final class AudioMixer
{
    private AudioMixFormat format_;

    /** Creates a mixer with the given output format. */
    this(AudioMixFormat format = AudioMixFormat.init)
    {
        format_ = format.normalized();
    }

    /** Returns the active output format. */
    AudioMixFormat format() const
    {
        return format_;
    }

    /** Updates the active output format. */
    void setFormat(AudioMixFormat format)
    {
        format_ = format.normalized();
    }

    /** Creates a cleared output buffer for a fixed frame count. */
    AudioMixBuffer createBuffer(size_t frames) const
    {
        AudioMixBuffer buffer;
        buffer.resize(frames, format_.channels);
        buffer.clear();
        return buffer;
    }

    /** Clears an existing output buffer. */
    void clear(ref AudioMixBuffer output) const
    {
        output.clear();
    }

    /** Mixes one interleaved source block into the output buffer.
     *
     * The source is assumed to match the output channel layout for now. Later
     * clip/stream loaders can add resampling or conversion before calling this.
     */
    void mixInterleaved(ref AudioMixBuffer output, const(float)[] source, AudioBusId bus, float gain, const(AudioSystem) audioSystem) const
    {
        if (source.length == 0 || output.samples.length == 0)
            return;

        const busGain = audioSystem is null ? 1.0f : audioSystem.effectiveBusVolume(bus);
        const finalGain = clampGain(gain) * busGain;
        const count = min(output.samples.length, source.length);
        foreach (index; 0 .. count)
            output.samples[index] = clampSample(output.samples[index] + source[index] * finalGain);
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
    private void assertNear(float actual, float expected)
    {
        const delta = actual > expected ? actual - expected : expected - actual;
        assert(delta < 0.0001f);
    }
}

unittest
{
    auto mixer = new AudioMixer();
    auto buffer = mixer.createBuffer(4);

    assert(buffer.channels == 2);
    assert(buffer.frameCount() == 4);
    foreach (sample; buffer.samples)
        assert(sample == 0.0f);
}

unittest
{
    auto audio = new AudioSystem();
    audio.applyVolumeSettings(0.5f, 1.0f, 0.25f);
    audio.processEvents();

    auto mixer = new AudioMixer();
    auto buffer = mixer.createBuffer(2);
    const source = [0.8f, -0.8f, 0.4f, -0.4f];

    mixer.mixInterleaved(buffer, source, AudioBusId.effects, 1.0f, audio);

    assertNear(buffer.samples[0], 0.1f);
    assertNear(buffer.samples[1], -0.1f);
    assertNear(buffer.samples[2], 0.05f);
    assertNear(buffer.samples[3], -0.05f);
}

unittest
{
    auto mixer = new AudioMixer();
    auto buffer = mixer.createBuffer(1);
    const loud = [2.0f, -2.0f];

    mixer.mixInterleaved(buffer, loud, AudioBusId.effects, 1.0f, null);
    mixer.mixInterleaved(buffer, loud, AudioBusId.effects, 1.0f, null);

    assertNear(buffer.samples[0], 1.0f);
    assertNear(buffer.samples[1], -1.0f);
}
