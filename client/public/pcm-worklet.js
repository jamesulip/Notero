// Capture worklet: context-rate Float32 in, 16 kHz PCM16 out.
//
// Plan section 8 warns that Safari and some Bluetooth mics silently ignore
// `new AudioContext({sampleRate: 16000})`, so this never assumes it got the
// rate it asked for -- it resamples from whatever `sampleRate` actually is.
//
// Downsampling is a box average over each output sample's input span, not
// nearest-neighbour picking. Decimating without averaging aliases anything
// above 8 kHz back down into the speech band, which is exactly where the
// consonant detail Whisper needs lives.

const TARGET_RATE = 16000;
const FRAMES_PER_MESSAGE = 1600; // 100 ms at 16 kHz

class PCMWorklet extends AudioWorkletProcessor {
  constructor() {
    super();
    this.ratio = sampleRate / TARGET_RATE;
    this.readPos = 0;      // fractional read cursor into the pending buffer
    this.pending = new Float32Array(0);
    this.out = new Int16Array(FRAMES_PER_MESSAGE);
    this.outLen = 0;
    this.peak = 0;
    this.muted = false;

    this.port.onmessage = (event) => {
      if (event.data && event.data.type === 'mute') {
        // Section 8: mute transmits silence rather than dropping frames, so
        // timestamps stay pinned to wall-clock and SRT exports don't desync.
        this.muted = !!event.data.value;
      }
    };
  }

  process(inputs) {
    const input = inputs[0];
    if (!input || input.length === 0) return true;
    const channel = input[0];
    if (!channel) return true;

    // Append this render quantum to whatever the last one left unconsumed.
    const merged = new Float32Array(this.pending.length + channel.length);
    merged.set(this.pending, 0);
    merged.set(channel, this.pending.length);

    let pos = this.readPos;
    while (pos + this.ratio <= merged.length) {
      const start = Math.floor(pos);
      const end = Math.min(Math.floor(pos + this.ratio), merged.length);
      let sum = 0;
      let count = 0;
      for (let i = start; i < end; i++) {
        sum += merged[i];
        count++;
      }
      let sample = count > 0 ? sum / count : 0;
      if (sample > this.peak) this.peak = sample;
      else if (-sample > this.peak) this.peak = -sample;
      if (this.muted) sample = 0;

      const clamped = Math.max(-1, Math.min(1, sample));
      this.out[this.outLen++] = clamped < 0 ? clamped * 0x8000 : clamped * 0x7fff;

      if (this.outLen === FRAMES_PER_MESSAGE) {
        const copy = this.out.slice(0);
        this.port.postMessage({ pcm: copy.buffer, peak: this.peak }, [copy.buffer]);
        this.outLen = 0;
        this.peak = 0;
      }
      pos += this.ratio;
    }

    // Keep the tail we haven't consumed, and carry the fractional offset.
    const consumed = Math.floor(pos);
    this.pending = merged.slice(consumed);
    this.readPos = pos - consumed;
    return true;
  }
}

registerProcessor('pcm-worklet', PCMWorklet);
