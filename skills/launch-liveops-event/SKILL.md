---
name: launch-liveops-event
description: "Playbook for running a measurable LiveOps event in a game (a double-XP weekend, a limited-time shop, a seasonal currency): configuration changes shipped as a holdout experiment with a staged rollout, a KPI dashboard, and a readout afterwards. Load when the user wants to plan, launch, or read out an in-game event."
---

# Launch a LiveOps event

An approach, not a script, for games with remote configuration. Without a holdout the studio
can't tell what the event did, so that part matters most.

1. **Understand the levers.** `list_configurations` and `get_configuration` (structure mode
   first) on the primary configuration: find the keys an event would change — multipliers,
   prices, rewards, feature toggles (load `understand-configurations`). If there's no
   configuration the event could change, say so: the event needs a remote-config key first. If
   the user gave only a theme ("a Halloween event"), propose concrete changes from the keys that
   exist.
2. **Pick the success metric** from the data: the core-loop event per player, session length, or
   revenue per player. Pick one guardrail (day-1 retention, or currency inflation).
3. **Agree the shape** with the user before building: the changes, the metric and guardrail, the
   dates, and a 90/10 or 80/20 split where the holdout keeps current values (`propose_plan` is a
   good way to show it, if you have it).
4. **Build it.**
   - The event as an experiment on the primary configuration (load `manage-experiments`): the
     treatment carries the event changeset, the control is the holdout. Use a staged rollout
     (load `experiment-rollouts`) so it ramps up. Check it with `preview_experiment` where
     available, then `create_experiment`.
   - A dashboard named after the event, with the metric and guardrail split by experiment group
     (load `manage-dashboards`).
5. Tell the user what goes live and when, and when the readout will be meaningful.
6. **Readout**, when the user returns or the event ends: `get_experiment_results`, report the
   lift on the metric and the guardrail, and recommend making it permanent, rerunning it with
   changes, or retiring it.
