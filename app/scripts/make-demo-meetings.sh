#!/usr/bin/env bash
# Builds the synthetic meetings behind the screenshots in README.md.
#
# The library of a real user holds real meetings. Those must never reach a
# screenshot in a public repository, thus the screenshots use these three
# invented meetings instead. Every word below is made up.
#
# Same voice reasoning as eval/make-synthetic.sh: macOS ships no Filipino
# voice, so the Indonesian and the Malay one stand in. Both are Austronesian
# and close enough in phonology to give a realistic token density. They still
# say Tagalog words incorrectly, therefore the transcript has more errors than
# real speech gives -- README.md says so next to the screenshots. The English
# voice takes the English-dominant turns, which is how a Taglish meeting
# actually sounds, and three distinct voices give the speaker model three
# genuinely different embeddings to separate.
#
# To fill a demo library with the output without touching your own recordings,
# point the app at a different home directory:
#
#     mkdir -p /tmp/demo/Library/Application\ Support/Transcriber
#     ln -s ~/Library/Application\ Support/Transcriber/Models \
#           /tmp/demo/Library/Application\ Support/Transcriber/Models
#     CFFIXED_USER_HOME=/tmp/demo app/Notero.app/Contents/MacOS/Notero
#
# CFFIXED_USER_HOME moves the store and the recordings; the symlink keeps the
# gigabytes of weights shared. `HOME` alone does nothing here, because
# `FileManager.urls(for: .applicationSupportDirectory)` ignores it. Then import
# each file with ⌘O. `open -a Notero file.wav` does nothing, because the app
# has no open-document handler.
set -euo pipefail
cd "$(dirname "$0")"
OUTDIR=${1:-demo-meetings}
mkdir -p "$OUTDIR"

M=Damayanti   # Maria
A=Amira       # Ana
B=Samantha    # Bea, the English-dominant one

start() { # start <output name>
    OUT="$OUTDIR/$1"
    TURNS=$(mktemp -d)
    i=0
}

turn() { # turn <voice> <rate> <text>
    i=$((i + 1))
    say -v "$1" -r "$2" "$3" -o "$TURNS/$(printf '%02d' $i).aiff"
    afconvert -f WAVE -d LEI16@16000 -c 1 \
        "$TURNS/$(printf '%02d' $i).aiff" "$TURNS/$(printf '%02d' $i).wav"
}

# Joins the turns into one 16 kHz mono WAV, which is what the app and the CLI
# both read, with 700 ms of silence between each. Speech with no gap gives the
# voice detector no boundary to cut on, and the whole meeting comes back as one
# turn with no speaker on it.
finish() {
    OUT="$OUT" TURNS="$TURNS" python3 -c '
import glob, os, wave

out_name, turns = os.environ["OUT"], os.environ["TURNS"]
parts = sorted(glob.glob(f"{turns}/*.wav"))
assert parts, "no turns rendered"
with wave.open(out_name, "wb") as out:
    out.setnchannels(1)
    out.setsampwidth(2)
    out.setframerate(16000)
    silence = b"\x00\x00" * int(16000 * 0.7)
    for i, name in enumerate(parts):
        with wave.open(name, "rb") as part:
            out.writeframes(part.readframes(part.getnframes()))
        if i != len(parts) - 1:
            out.writeframes(silence)
'
    rm -rf "$TURNS"
    echo "wrote $OUT"
}

# ---------------------------------------------------------------- meeting one

start "Sprint Planning.wav"
turn $M 170 "Okay, good morning everyone. Start na tayo, medyo tight ang schedule ko today. Ang agenda natin ay tatlo lang: yung status ng onboarding redesign, ang budget para sa next quarter, at yung deployment concern na na-raise last week."
turn $A 175 "Sige. Ako muna sa onboarding. Tapos na yung design review, pero medyo delayed kami ng one week kasi hindi pa natapos ang testing sa staging environment."
turn $M 170 "One week lang ba talaga, o mas matagal? Kailangan ko kasing sabihin kay client bukas."
turn $A 175 "One week po. Confident ako dyan basta ma-prioritize namin yung staging this week. Kung hindi, saka lang mag-slip."
turn $B 180 "Can I jump in on that? Ang problema kasi sa staging, we only have one environment and the QA team is sharing it with the payments work. So kahit i-prioritize natin, mag-queue pa rin tayo."
turn $M 170 "Ah, okay. So hindi testing ang bottleneck, kundi yung environment. Pwede ba tayo mag-spin up ng pangalawa?"
turn $B 180 "Yes, but somebody has to own it. Mga two days of setup, and then it needs a budget line for the extra compute."
turn $M 170 "Sige, decision na natin yan: mag-spin up tayo ng second staging environment. Bea, ikaw ang mag-own, and ilagay natin sa Q4 budget yung compute. Ana, i-move mo yung onboarding testing dun pag ready na."
turn $A 175 "Noted. Ako na mag-update sa timeline pagkatapos nito."
turn $M 170 "Salamat. Next, budget review. Ana, magkano ang na-consume natin so far this quarter?"
turn $A 175 "Mga sixty-eight percent po ng allocation. Malaking part dyan yung contractor para sa design system, na tapos na naman last month."
turn $B 180 "So we have room for the compute, then. I will send the exact number after I check the pricing, probably by Thursday."
turn $M 170 "Perfect. Last item, yung deployment concern. Ano na ang nangyari dun?"
turn $B 180 "Still open. The rollback took forty minutes last time, which is way too long. I want to propose a change to the deploy pipeline, but I need one more week to write it up properly."
turn $M 170 "Okay, hindi na natin i-decide today. Bea, i-write up mo, and balikan natin next week. Sige, tapos na tayo. Salamat sa lahat, and mag-follow up ako sa client mamaya."
finish

# ---------------------------------------------------------------- meeting two

start "Client Check-in.wav"
turn $M 170 "Hi, thanks for making time. Quick update lang from our side, then open natin for questions."
turn $B 180 "Sounds good. We have about twenty minutes."
turn $M 170 "Okay. Yung onboarding redesign, on track pa rin para sa end of the month, pero may isang week na buffer na nawala sa amin sa testing. Hindi ito makakaapekto sa launch date."
turn $B 180 "Understood. As long as the launch date holds, we are fine. Ano ang risk kung sakaling ma-slip pa?"
turn $M 170 "Kung ma-slip pa ng another week, kailangan nating i-cut yung analytics dashboard sa first release, at i-follow na lang sa next update."
turn $B 180 "Let us keep that as the fallback then. Please flag it early if you see it coming."
finish

# -------------------------------------------------------------- meeting three

start "Design Review.wav"
turn $A 175 "Ito na yung bagong empty state. Ang goal kasi natin, hindi lang blank screen ang makita ng user sa first launch."
turn $B 180 "I like it. But the copy is doing two jobs at once. It explains what the app does and it also asks the user to do something."
turn $A 175 "Tama. Pwede natin hatiin: yung heading para sa explanation, tapos yung button na lang ang call to action."
turn $B 180 "Yes. And can we make the button label a verb? Start Recording, instead of Get Started."
turn $A 175 "Sige, gawin ko yun. Isa pa, tinanggal ko yung illustration sa taas kasi masyadong mabigat sa dark mode."
turn $B 180 "Agreed, that was distracting. Send me the revision and I will approve it today."
finish
