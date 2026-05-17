/** Backend-neutral audio event and bus state scaffolding.
 *
 * This module intentionally does not open an audio device yet. It defines the
 * frame-facing API that UI and gameplay code can use before the SDL backend,
 * mixer, clips, and streaming music are added.
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.audio.audio_system;

private enum size_t audioBusCount = 4;

/** Logical audio routing groups used by the first engine audio model. */
enum AudioBusId
{
    /** Top-level volume applied to all non-master buses. */
    master,
    /** Streamed music and longer ambience tracks. */
    music,
    /** Gameplay and demo sound effects. */
    effects,
    /** UI feedback sounds; follows the effects setting until a dedicated setting exists. */
    ui,
}

/** Typed audio command emitted by gameplay, UI, or demo code. */
enum AudioEventKind
{
    /** Change a bus volume immediately. */
    setBusVolume,
    /** Play a short preloaded clip once clips and a mixer exist. */
    playClip,
    /** Stop all active voices on a bus. */
    stopAll,
    /** Start streamed music once stream playback exists. */
    startMusic,
    /** Stop streamed music once stream playback exists. */
    stopMusic,
    /** Move a bus toward a target volume over time. */
    fadeBus,
}

/** State for one logical audio bus. */
struct AudioBusState
{
    /** Bus identifier. */
    AudioBusId id;
    /** Current normalized volume in the range 0..1. */
    float volume = 1.0f;
    /** Target normalized volume used by later fade updates. */
    float targetVolume = 1.0f;
    /** Remaining fade duration placeholder in seconds. */
    float fadeSeconds;
}

/** Small serializable audio command.
 *
 * Asset names are symbolic for now. The later asset layer can replace them
 * with stable handles without changing the event flow.
 */
struct AudioEvent
{
    /** Event kind. */
    AudioEventKind kind;
    /** Target bus for routed events. */
    AudioBusId bus = AudioBusId.effects;
    /** Symbolic clip or track id. */
    string assetId;
    /** Normalized gain or volume value depending on event kind. */
    float gain = 1.0f;
    /** Target volume for fade events. */
    float targetVolume = 1.0f;
    /** Fade duration in seconds. */
    float durationSeconds;
    /** Whether a future voice or stream should loop. */
    bool loop;

    /** Creates an immediate bus-volume event. */
    static AudioEvent setBusVolume(AudioBusId bus, float volume)
    {
        AudioEvent event;
        event.kind = AudioEventKind.setBusVolume;
        event.bus = bus;
        event.gain = clampUnit(volume);
        event.targetVolume = event.gain;
        return event;
    }

    /** Creates a short-clip playback event. */
    static AudioEvent playClip(string assetId, AudioBusId bus = AudioBusId.effects, float gain = 1.0f)
    {
        AudioEvent event;
        event.kind = AudioEventKind.playClip;
        event.bus = bus;
        event.assetId = assetId;
        event.gain = clampUnit(gain);
        return event;
    }

    /** Creates a stop-all event for one bus. */
    static AudioEvent stopAll(AudioBusId bus)
    {
        AudioEvent event;
        event.kind = AudioEventKind.stopAll;
        event.bus = bus;
        return event;
    }

    /** Creates a streamed-music start event. */
    static AudioEvent startMusic(string trackId, float gain = 1.0f, bool loop = true)
    {
        AudioEvent event;
        event.kind = AudioEventKind.startMusic;
        event.bus = AudioBusId.music;
        event.assetId = trackId;
        event.gain = clampUnit(gain);
        event.loop = loop;
        return event;
    }

    /** Creates a streamed-music stop event. */
    static AudioEvent stopMusic(float fadeSeconds = 0.0f)
    {
        AudioEvent event;
        event.kind = AudioEventKind.stopMusic;
        event.bus = AudioBusId.music;
        event.durationSeconds = clampNonNegative(fadeSeconds);
        return event;
    }

    /** Creates a bus fade event. */
    static AudioEvent fadeBus(AudioBusId bus, float targetVolume, float durationSeconds)
    {
        AudioEvent event;
        event.kind = AudioEventKind.fadeBus;
        event.bus = bus;
        event.targetVolume = clampUnit(targetVolume);
        event.gain = event.targetVolume;
        event.durationSeconds = clampNonNegative(durationSeconds);
        return event;
    }
}

/** Frame-facing owner for audio events and bus volumes.
 *
 * The first implementation records intent and applies bus-volume state. Later
 * revisions can let the same event queue feed a device-backed mixer.
 */
final class AudioSystem
{
    private AudioBusState[audioBusCount] buses;
    private AudioEvent[] pendingEvents;

    /** Creates an audio system with all buses at full volume. */
    this()
    {
        reset();
    }

    /** Clears events and restores all bus state to full volume. */
    void reset()
    {
        pendingEvents.length = 0;
        foreach (index; 0 .. buses.length)
        {
            buses[index] = AudioBusState(cast(AudioBusId)index, 1.0f, 1.0f, 0.0f);
        }
    }

    /** Queues an audio event for the next processing step. */
    void emit(AudioEvent event)
    {
        normalizeEvent(event);
        pendingEvents ~= event;
    }

    /** Returns how many events are waiting to be processed. */
    size_t pendingEventCount() const
    {
        return pendingEvents.length;
    }

    /** Drops queued events without changing bus state. */
    void clearEvents()
    {
        pendingEvents.length = 0;
    }

    /** Queues volume changes that match the existing demo settings model.
     *
     * The UI bus follows the effects value until the settings model gains a
     * dedicated UI volume.
     */
    void applyVolumeSettings(float masterVolume, float musicVolume, float effectsVolume)
    {
        emit(AudioEvent.setBusVolume(AudioBusId.master, masterVolume));
        emit(AudioEvent.setBusVolume(AudioBusId.music, musicVolume));
        emit(AudioEvent.setBusVolume(AudioBusId.effects, effectsVolume));
        emit(AudioEvent.setBusVolume(AudioBusId.ui, effectsVolume));
    }

    /** Applies all queued events that can affect current scaffolding state. */
    uint processEvents()
    {
        auto events = pendingEvents;
        pendingEvents.length = 0;

        foreach (event; events)
        {
            applyEvent(event);
        }

        return cast(uint)events.length;
    }

    /** Sets a bus volume immediately, bypassing the queue. */
    void setBusVolumeNow(AudioBusId bus, float volume)
    {
        auto index = busIndex(bus);
        buses[index].volume = clampUnit(volume);
        buses[index].targetVolume = buses[index].volume;
        buses[index].fadeSeconds = 0.0f;
    }

    /** Returns the current normalized volume for one bus. */
    float busVolume(AudioBusId bus) const
    {
        return buses[busIndex(bus)].volume;
    }

    /** Returns the effective bus gain after master-volume multiplication. */
    float effectiveBusVolume(AudioBusId bus) const
    {
        if (bus == AudioBusId.master)
            return busVolume(AudioBusId.master);
        return busVolume(AudioBusId.master) * busVolume(bus);
    }

    /** Returns the retained state for one bus. */
    AudioBusState busState(AudioBusId bus) const
    {
        return buses[busIndex(bus)];
    }

    private void applyEvent(AudioEvent event)
    {
        normalizeEvent(event);

        final switch (event.kind)
        {
            case AudioEventKind.setBusVolume:
                setBusVolumeNow(event.bus, event.gain);
                break;
            case AudioEventKind.fadeBus:
                auto index = busIndex(event.bus);
                buses[index].targetVolume = event.targetVolume;
                buses[index].fadeSeconds = event.durationSeconds;
                if (event.durationSeconds == 0.0f)
                    buses[index].volume = event.targetVolume;
                break;
            case AudioEventKind.playClip:
            case AudioEventKind.stopAll:
            case AudioEventKind.startMusic:
            case AudioEventKind.stopMusic:
                break;
        }
    }
}

private size_t busIndex(AudioBusId bus)
{
    return cast(size_t)bus;
}

private float clampUnit(float value)
{
    if (value < 0.0f)
        return 0.0f;
    if (value > 1.0f)
        return 1.0f;
    return value;
}

private float clampNonNegative(float value)
{
    if (value < 0.0f)
        return 0.0f;
    return value;
}

private void normalizeEvent(ref AudioEvent event)
{
    event.gain = clampUnit(event.gain);
    event.targetVolume = clampUnit(event.targetVolume);
    event.durationSeconds = clampNonNegative(event.durationSeconds);
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
    auto audio = new AudioSystem();

    audio.applyVolumeSettings(0.7f, 0.5f, 0.25f);

    assert(audio.pendingEventCount() == 4);
    assert(audio.processEvents() == 4);
    assert(audio.pendingEventCount() == 0);

    assertNear(audio.busVolume(AudioBusId.master), 0.7f);
    assertNear(audio.busVolume(AudioBusId.music), 0.5f);
    assertNear(audio.busVolume(AudioBusId.effects), 0.25f);
    assertNear(audio.busVolume(AudioBusId.ui), 0.25f);
    assertNear(audio.effectiveBusVolume(AudioBusId.music), 0.35f);
}

unittest
{
    auto audio = new AudioSystem();

    audio.emit(AudioEvent.setBusVolume(AudioBusId.master, 2.0f));
    audio.emit(AudioEvent.setBusVolume(AudioBusId.effects, -1.0f));
    audio.emit(AudioEvent.fadeBus(AudioBusId.music, 0.4f, -5.0f));

    assert(audio.processEvents() == 3);
    assertNear(audio.busVolume(AudioBusId.master), 1.0f);
    assertNear(audio.busVolume(AudioBusId.effects), 0.0f);
    assertNear(audio.busState(AudioBusId.music).targetVolume, 0.4f);
    assertNear(audio.busState(AudioBusId.music).fadeSeconds, 0.0f);
    assertNear(audio.busVolume(AudioBusId.music), 0.4f);
}

unittest
{
    auto audio = new AudioSystem();

    audio.emit(AudioEvent.playClip("ui/click", AudioBusId.ui, 0.5f));
    audio.emit(AudioEvent.startMusic("music/theme", 0.8f));
    assert(audio.pendingEventCount() == 2);

    audio.clearEvents();
    assert(audio.pendingEventCount() == 0);
}
