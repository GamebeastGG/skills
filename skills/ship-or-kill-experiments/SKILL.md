---
name: ship-or-kill-experiments
description: "Playbook for deciding running experiments: read each one's results, decide ship, end, extend, or ramp with explicit rules (sample-ratio checks, power, duration), and apply the decision. Load when the user asks whether an experiment is done, which one won, or what to do with running experiments."
---

# Ship or kill experiments

An approach, not a script. If the user named an experiment, review only that one; review every
running experiment only when they ask about all of them. Load `understand-experiments` to read
results, and `manage-experiments` before changing anything.

1. For each experiment in scope, `get_experiment_results`. Note the lift on the primary metric,
   its 95% interval, the verdict, days running, enrolled units, and the sample-ratio check.
2. Decide with these rules. Never call a winner on an inconclusive result.
   - **Sample-ratio mismatch**: don't trust the result. Investigate the assignment first.
   - **Significant win**: ship. Roll the winning changeset into the base configuration with
     `update_configuration`, then end the experiment with `terminate_experiment`.
   - **Significant loss**: end it with `terminate_experiment`.
   - **Inconclusive and under-powered** (fewer than about 1,000 units per group, or under 14
     days): extend it. If it's on a staged rollout that is paused or low, ramp it with
     `update_experiment_rollout` (load `experiment-rollouts`).
   - **Inconclusive after 21 or more days with enough units**: end it. The effect is too small
     to matter.
3. Give the recommendation with its evidence before acting. When several experiments change at
   once, lay the decisions out first (with `propose_plan`, if you have it). Each change goes
   through its own approval.
4. Finish with a short readout: experiment, decision, lift, and what changed.
