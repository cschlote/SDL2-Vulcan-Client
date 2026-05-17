/** SDL audio device ownership for the engine audio layer.
 *
 * The device owner is intentionally small: it opens, pauses/resumes, queries,
 * and closes the SDL playback device. Mixing, streams, clips, and callbacks are
 * added in later modules so renderer and demo code do not own backend details.
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.audio.audio_device;

import bindbc.sdl : SDL_AudioDevice, SDL_AudioDeviceID, SDL_AudioFormat, SDL_AudioSpec,
    SDL_AudioStream, SDL_AudioDevicePaused, SDL_AudioStreamDevicePaused,
    SDL_ClearAudioStream, SDL_CloseAudioDevice, SDL_DestroyAudioStream,
    SDL_GetAudioDeviceFormat, SDL_GetAudioStreamDevice, SDL_GetAudioStreamQueued,
    SDL_OpenAudioDevice, SDL_OpenAudioDeviceStream, SDL_PauseAudioDevice,
    SDL_PauseAudioStreamDevice, SDL_PutAudioStreamData, SDL_ResumeAudioDevice,
    SDL_ResumeAudioStreamDevice;

private enum SDL_AudioDeviceID invalidAudioDeviceId = 0;

/** Desired playback device format for the first SDL backend. */
struct AudioDeviceConfig
{
    /** Requested sample rate in Hz. */
    int frequency = 48_000;
    /** Requested channel count. */
    int channels = 2;
    /** Requested sample format. */
    SDL_AudioFormat format = SDL_AudioFormat.f32;
    /** Preferred callback/mixer block size. SDL may choose another value. */
    int sampleFrames = 512;

    /** Returns the clamped SDL spec used for device opening. */
    SDL_AudioSpec toSdlSpec() const
    {
        SDL_AudioSpec spec;
        spec.freq = frequency > 0 ? frequency : 48_000;
        spec.channels = channels > 0 ? channels : 2;
        spec.format = format;
        return spec;
    }
}

/** Actual playback device format reported by SDL after opening. */
struct AudioDeviceInfo
{
    /** Actual sample rate in Hz. */
    int frequency;
    /** Actual channel count. */
    int channels;
    /** Actual sample format. */
    SDL_AudioFormat format;
    /** Actual or backend-recommended sample frame count, when SDL reports one. */
    int sampleFrames;
}

/** Owns one SDL playback device handle. */
final class AudioDevice
{
    private SDL_AudioDeviceID deviceId = invalidAudioDeviceId;
    private SDL_AudioStream* stream;
    private bool streamOwned;
    private AudioDeviceConfig requestedConfig;
    private AudioDeviceInfo actualInfo;

    /** Returns true after a playback device was opened successfully. */
    bool isOpen() const
    {
        return deviceId != invalidAudioDeviceId;
    }

    /** Returns the SDL device id, or 0 when closed. */
    SDL_AudioDeviceID id() const
    {
        return deviceId;
    }

    /** Returns true when output uses an SDL audio stream. */
    bool hasStream() const
    {
        return stream !is null;
    }

    /** Returns the requested config used by the last `open` call. */
    AudioDeviceConfig requested() const
    {
        return requestedConfig;
    }

    /** Returns the last actual format reported by SDL. */
    AudioDeviceInfo actual() const
    {
        return actualInfo;
    }

    /** Opens the default playback device with the supplied config.
     *
     * Returns true on success. The method leaves an already-open device alone
     * so callers can safely retry setup without leaking handles.
     */
    bool open(AudioDeviceConfig config = AudioDeviceConfig.init)
    {
        if (isOpen())
            return true;

        requestedConfig = config;
        auto spec = config.toSdlSpec();
        deviceId = SDL_OpenAudioDevice(SDL_AudioDevice.defaultPlayback, &spec);
        if (!isOpen())
            return false;

        refreshActualInfo();
        return true;
    }

    /** Opens the default playback device as an SDL audio stream.
     *
     * The source format is the requested engine mix format. SDL converts it to
     * the actual hardware format behind the stream.
     */
    bool openStream(AudioDeviceConfig config = AudioDeviceConfig.init)
    {
        if (hasStream())
            return true;

        if (isOpen())
            close();

        requestedConfig = config;
        auto spec = config.toSdlSpec();
        stream = SDL_OpenAudioDeviceStream(SDL_AudioDevice.defaultPlayback, &spec, null, null);
        if (stream is null)
            return false;

        streamOwned = true;
        deviceId = SDL_GetAudioStreamDevice(stream);
        refreshActualInfo();
        return true;
    }

    /** Closes the SDL playback device if it is open. */
    void close()
    {
        if (hasStream())
        {
            SDL_DestroyAudioStream(stream);
            stream = null;
            streamOwned = false;
            deviceId = invalidAudioDeviceId;
            actualInfo = AudioDeviceInfo.init;
            return;
        }

        if (!isOpen())
            return;

        SDL_CloseAudioDevice(deviceId);
        deviceId = invalidAudioDeviceId;
        actualInfo = AudioDeviceInfo.init;
    }

    /** Starts device playback if the device is open. */
    bool resume()
    {
        if (hasStream())
            return SDL_ResumeAudioStreamDevice(stream);
        return isOpen() && SDL_ResumeAudioDevice(deviceId);
    }

    /** Pauses device playback if the device is open. */
    bool pause()
    {
        if (hasStream())
            return SDL_PauseAudioStreamDevice(stream);
        return isOpen() && SDL_PauseAudioDevice(deviceId);
    }

    /** Returns true while SDL reports the device as paused or while closed. */
    bool paused()
    {
        if (hasStream())
            return SDL_AudioStreamDevicePaused(stream);
        return !isOpen() || SDL_AudioDevicePaused(deviceId);
    }

    /** Queues interleaved float samples into the SDL stream. */
    bool queueInterleavedFloat(const(float)[] samples)
    {
        if (!hasStream() || samples.length == 0)
            return false;

        return SDL_PutAudioStreamData(stream, samples.ptr, cast(int)(samples.length * float.sizeof));
    }

    /** Returns how many bytes are queued in the SDL audio stream. */
    int queuedBytes()
    {
        return hasStream() ? SDL_GetAudioStreamQueued(stream) : 0;
    }

    /** Clears queued stream data without closing the device. */
    bool clearQueued()
    {
        return hasStream() && SDL_ClearAudioStream(stream);
    }

    /** Refreshes the actual device format cached after opening. */
    bool refreshActualInfo()
    {
        if (!isOpen())
            return false;

        SDL_AudioSpec spec;
        int sampleFrames;
        if (!SDL_GetAudioDeviceFormat(deviceId, &spec, &sampleFrames))
            return false;

        actualInfo = AudioDeviceInfo(spec.freq, spec.channels, spec.format, sampleFrames);
        return true;
    }

    ~this()
    {
        close();
    }
}

unittest
{
    AudioDeviceConfig config;
    config.frequency = 44_100;
    config.channels = 1;
    config.format = SDL_AudioFormat.s16;
    config.sampleFrames = 256;

    const spec = config.toSdlSpec();
    assert(spec.freq == 44_100);
    assert(spec.channels == 1);
    assert(spec.format == SDL_AudioFormat.s16);
}

unittest
{
    AudioDeviceConfig config;
    config.frequency = -1;
    config.channels = 0;

    const spec = config.toSdlSpec();
    assert(spec.freq == 48_000);
    assert(spec.channels == 2);
}

unittest
{
    auto device = new AudioDevice();

    assert(!device.isOpen());
    assert(device.id() == invalidAudioDeviceId);
    assert(!device.hasStream());
    assert(device.paused());
    assert(device.queuedBytes() == 0);
}
