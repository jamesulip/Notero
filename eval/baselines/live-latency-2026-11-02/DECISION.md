# Decision

Rule: unchanged unless every gate passes; the feature flag stays off otherwise.

Reproducibility: every rule above holds in session 1 AND in session 2, which runs later, in its own invocation, on the clips of session 1 and the held-out clips.

* **ADA**: session 1: latency 17.1%, fails latency, missingSpeech, hallucinations, uncontended; session 2: latency 16.7%, fails latency, uncontended -> default stays
* **CTX**: session 1: latency 8.2%, fails latency, wer, missingSpeech, hallucinations, uncontended; session 2: not run -> default stays
* **HOP**: session 1: latency 10.0%, fails latency, missingSpeech, hallucinations, uncontended; session 2: not run -> default stays
* **HT**: session 1: latency 0.6%, fails latency, missingSpeech, uncontended; session 2: latency 14.5%, fails latency, missingSpeech, hallucinations, uncontended -> default stays
* **PRE**: session 1: latency -10.3%, fails latency, wer, missingSpeech, hallucinations, uncontended; session 2: not run -> default stays
* **VAD**: session 1: latency -1.4%, fails latency, wer, hallucinations, uncontended; session 2: not run -> default stays

**Production configuration UNCHANGED.**
