---
name: target-segment
description: "Playbook for finding the players a change should reach and reaching them: build and sanity-check a cohort definition, then target an experiment at it. Load when the user wants to reach a specific group of players, or asks which players a change should be aimed at."
---

# Target a segment

An approach, not a script. Start from the user's goal; when they haven't given one, suggest the
segment the data supports best and say why. Load `cohorts` to build the definition.

1. **Pick the segment.** From the user's goal, or one of these when the data supports it:
   - Players who tried the core loop but never came back (day-1 churners).
   - Players who opened the shop but never bought.
   - High-engagement players who haven't paid.
   - Top spenders or most engaged players relative to everyone else (top 1%, above average).
     Use a ranked condition (`math.relative` in `cohorts`) rather than guessing a fixed amount.
2. **Build and check it.** Build the cohort definition, run it to get the member count, and
   sanity-check the count. A segment of 0, or one that's nearly everyone, means the definition is
   wrong; fix it.
3. **Agree what to do with it**: usually an experiment targeted at the cohort (load
   `manage-experiments`), with a treatment aimed at the segment's problem (an onboarding tweak for
   churners, a starter offer for shop browsers).
4. In the Gamebeast assistant the user saves the cohort from its card. Then create the experiment
   targeting it, with approval.
5. Report the size, the targeting, and when results will be readable.
