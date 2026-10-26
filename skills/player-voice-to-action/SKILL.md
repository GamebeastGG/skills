---
name: player-voice-to-action
description: "Playbook for turning community feedback into a testable change: find the topic players care about most, check it against behavioral data, find the configuration lever, and recommend an experiment or fix. Load when the user asks what players are complaining about or how to act on feedback."
---

# Turn player voice into action

An approach, not a script. If the user named a topic, start from it. Load
`understand-community-pulse` to read sentiment.

1. `list_sentiment_sources`. If there are none, say so in one sentence, point the user to
   Community Pulse to connect a Discord or other source, and stop.
2. `get_community_pulse` for the last 14 days. Pick the topic with the most negative volume that
   is rising (or the one the user named). Pull 3 representative quotes with `query_sentiment`.
3. **Check it against behavior.** Map the topic to events ("the grind is too slow" maps to
   progression events and level-up time; "shop prices" maps to purchase conversion), then build
   and run the spec. Say plainly whether the data agrees: a loud complaint with no behavioral
   signal is worth a reply, not a change.
4. **Find the lever** with `search_configuration`.
5. **Propose the change.** An experiment when the effect is uncertain, which is the default; a
   direct configuration edit only for clear bugs, such as a broken price. Each change goes
   through its own approval.
6. Give the studio a one-line message they can post to their community about the fix.
