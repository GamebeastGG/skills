---
name: tune-economy
description: "Playbook for finding and fixing an imbalance in a game's in-game economy (inflation, a dominant source, an unused sink, a stalled premium conversion) and shipping the fix as a measurable, reversible experiment. Load when the user asks about currency balance, prices, rewards, or inflation."
---

# Tune a game economy

An approach, not a script, for games with a currency. If the user already named the problem
("gems are too easy to get"), start at step 3.

1. **Map the economy.** Find the currency events with `list_event_types` (earned, spent,
   rewarded, purchased). For each currency, chart total earned and total spent per active player
   per day over 28 days, broken down by source and by sink. If there are no currency events, say
   so: the economy has to be instrumented first (the `instrument-game` playbook covers it).
2. **Find the imbalance.** Common patterns:
   - Earning outpaces spending (inflation: balances grow and sinks stop mattering).
   - One source dominates (an exploit or an overtuned reward).
   - A sink nobody uses (an overpriced item).
   - A premium currency conversion that stalls.
   Quantify it.
3. **Find the lever.** `search_configuration` for the reward, price, or rate keys behind that
   source or sink (load `understand-configurations`).
4. **Agree the change**: the imbalance, the key, the new value, the success metric (the
   earn/spend ratio), and a guardrail (retention, or revenue per player).
5. **Ship it as an experiment**, never as a blind edit to the primary configuration: a treatment
   that changes the key (load `manage-experiments`), a staged rollout starting around 10% (load
   `experiment-rollouts`), checked with `preview_experiment` where available.
6. Say when results will be readable given the traffic, and what result would justify shipping.
