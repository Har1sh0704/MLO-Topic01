# Wi-Fi 7 multi-link operation under unequal congestion
## Simulation code — EEEN3008J group 15, topic 01

Two-link packet-queue simulator for the question *"when does a second Wi-Fi
link reduce delay, and when does poor link selection make it worse?"*.

Base MATLAB only (R2019b or newer). **No toolbox is needed** — in particular
`prctile`, `tinv`, `poissrnd` and `bootci` are all replaced by local functions,
because the machine this was developed on has base MATLAB only.

```matlab
run_all          % validate + run every grid + draw every figure (~30 s)
```

## Files

| File | Purpose |
|---|---|
| `default_cfg.m` | every parameter in one place, each tagged measured (M) / illustrative (I) |
| `simulate_mlo.m` | the simulator: queue, channel, retuning, link-selection policies, metrics |
| `make_channel.m` | busy/idle (ON/OFF, Gilbert–Elliott) traces for both links, optional common interferer |
| `make_arrivals.m` | Poisson arrival trace for one replication |
| `prctile_b.m` | percentile with linear interpolation (no Statistics Toolbox) |
| `tcrit95.m` | Student-t 95 % critical value (no Statistics Toolbox) |
| `validate_model.m` | 10 known-answer checks that must pass before any result is trusted |
| `run_experiments.m` | the four experiment grids + CSV export |
| `plot_figures.m` | figures 1–6 as PNG (300 dpi) and vector PDF |
| `run_all.m` | runs everything |

## Model, stated precisely

* **Slot**: one transmission opportunity on a link, ~1 ms (OFDMA time-unit
  granularity). Every delay below is in slots.
* **Traffic**: one MAC queue shared by both links, Poisson arrivals at
  λ packets/slot, finite buffer of `Qcap` packets, drop-tail.
* **Service**: a link carries at most one packet per slot, and only while it
  is idle. Capacity is binary — 1 or 0 packets per slot. No collisions, no
  retransmission, no aggregation, no rate adaptation.
* **Channel**: each link alternates busy (a foreign OBSS occupies the channel
  and CCA reports busy) and idle periods with exponentially distributed run
  lengths, so the long-run busy fraction is exactly `b(l)` (default 0.10 and
  0.60). `runCV > 1` makes the congestion bursty; `shared > 0` puts part of the
  busy time on **both** links, which is how the co-blocked case is built.
* **Radio**: one transmit chain. Using one link excludes the other, and
  changing link costs `swDelay` slots of airtime, charged exactly (validated).
* **Sensing**: passive CCA on both links is assumed available even while
  transmitting on one of them. Monitoring is free; retuning is not. This is the
  one assumption that a two-radio front end would relax.
* **Delay** is measured from arrival to the end of the packet's transmission
  slot, so it includes one slot of service time.

## Policies

| Name | Rule |
|---|---|
| `single_best` | static association to the less congested link |
| `single_worst` | static association to the more congested link (what a bad band choice costs) |
| `rr` | round robin with a fixed dwell per link — blind to the channel |
| `greedy` | switch as soon as the tuned link is busy and the other is idle; no cost or backlog test |
| `proposed` | queue + busy-time rule (below) |
| `oracle` | the same rule fed the true busy fraction and mean run length |
| `dual` | two radios, both links usable in the same slot (hardware bound) |

### The proposed rule

Two triggers, both evaluated only when the tuned link is **busy** (if it is
idle, transmitting is always the right move) and the other link is **idle**:

1. **Structural preference.** Move if the long-run availability gain
   `(1-p_alt) - (1-p_cur)` exceeds the retuning cost amortised over a horizon
   `H`, where `H` grows with the backlog. `p` is an EWMA estimate of the busy
   probability, so no oracle knowledge is used.
2. **Outage escape.** Otherwise, escape only once the outage has already
   lasted at least `swDelay` slots *and* the estimated **residual** outage
   exceeds the retuning cost. The residual is the conditional mean of the
   remaining outage given that the outage already exceeds the observed length,
   taken over the last 64 completed outages on that link. When the backlog is
   deep (airtime-limited regime) the threshold is raised to the round-trip
   cost, because then the retune has to pay for the eventual return as well.

Ingredient (2) is the whole point: it is what a plain "the other link is idle,
so move" rule cannot do, and it is what stops the radio from retuning for an
outage that was about to end.

## Validation (`validate_model.m`)

| # | Check | Result |
|---|---|---|
| 1–2 | M/D/1 mean delay at ρ = 0.5 and 0.8 vs `1 + ρ/(2(1−ρ))` | 1.503 / 3.008 vs 1.5 / 3.0 |
| 3 | arrival-rate estimator | 0.4997 vs 0.50 |
| 4 | packet conservation, all 7 policies | exact |
| 5 | saturation: load 1.2 on capacity 1.0 | goodput 1.000, drop rate 16.7 % |
| 6 | utilisation with one link used | 0.5013 vs 0.50 |
| 7 | realised busy fraction of the channel model | 0.857 vs 0.85 |
| 8 | a second radio doubles capacity | goodput 1.498 at load 1.5 |
| 9 | round robin splits identical links evenly | 0.247 / 0.247 |
| 10 | a forced retune costs exactly `swDelay` | exactly 5 slots |

Test 10 is the one that matters for fairness: an off-by-one in the retune
countdown would silently give every switching policy a free slot, or charge it
twice.

## Experiment grids (`run_experiments.m`)

| Grid | Design | Purpose |
|---|---|---|
| 1 | 5 congestion scenarios × 3 loads (20/50/80 % of combined capacity) × 7 policies × 10 seeds = 1050 runs | the main comparison |
| 2 | 2 scenarios × 2 loads × 5 retuning costs (0–8 slots) × 4 policies | how much retuning can be afforded |
| 3 | one point, full delay distribution | tail shape |
| 4 | co-blocked fraction 0 → 30 % at fixed load | when the second link stops helping |
| 5 | mean busy-run length 1.8 → 60 slots at 20 % and 50 % load | the crossover between helping and hurting |

Scenarios: **A** balanced (0.20/0.20), **B** moderate imbalance (0.10/0.60),
**C** severe imbalance (0.05/0.85), **D** co-blocked (0.30/0.30 with 100 % of
the busy time from a common interferer), **E** bursty balanced (0.15/0.15,
run-length CV 2.5).

Every policy inside one (scenario, load, seed) cell sees the **same** arrival
trace and the **same** channel realisation, so the comparison is paired and the
confidence intervals are computed across the 10 seeds (Student t, 9 df), not
across packets.

## What the results say

1. **A state-aware second link cuts tail delay by more than an order of
   magnitude.** Balanced scenario, 50 % of combined capacity: p95 delay
   719 → 55 slots (proposed), 22 slots with two radios. At 20 % load,
   80 → 9 slots.
2. **Blind link selection is worse than no link selection.** Round robin
   spends whole dwells on a blocked link and pays a retune at every boundary:
   p95 1168 slots vs 47 for a single static link in scenario B at 50 % load,
   and it loses 26 % of the offered packets instead of 0 %. This is the direct
   answer to "when does poor link selection make it worse".
3. **Extra capacity is not the whole story.** All MLO schemes have access to
   the same two links, so the spread between `rr`, `greedy` and `proposed` is
   pure scheduling quality; the gap to `dual` is what an extra radio chain
   would buy (goodput 0.93 → 1.28 at 80 % load in scenario A).
4. **The gain disappears when the congestion is correlated.** With 30 % of the
   busy time caused by an interferer heard on both links, every single-radio
   scheme converges to the single-link curve (p95 843 slots at 50 % load);
   only the second radio chain still helps.
5. **A heavily congested second link is not worth switching to.** In scenario
   C (0.05/0.85) the proposed rule leaves the radio where it is and gains
   almost nothing over a single link (57.0 → 54.0 slots at 80 % load). This is
   the "extra link gives little benefit" case the brief asks for.
6. **Switching pays only if the outage outlasts the retune.** Sweeping the mean
   busy-run length shows the crossover: below roughly one retuning time
   (~4 slots), the greedy rule is *worse* than staying on one link (13.7 vs
   11.0 slots at 20 % load), because it retunes 73 times per 1000 slots for
   outages that were about to end. The proposed rule retunes 7 times per 1000
   slots there and never loses to the single-link baseline.
7. **A null result, honestly stated.** In the memoryless regime the simple
   `greedy` rule is within a few percent of `proposed` and of the oracle. With
   a single queue and no per-link traffic there is little for a cleverer rule
   to exploit once outages are long; the rule's value is that it never does
   *worse*, which is exactly where the naive rule fails (point 6).

## Figures

| Figure | Content |
|---|---|
| `fig1_delay_vs_load` | p95 delay vs offered load, 4 scenarios, all policies, 95 % CI |
| `fig2_goodput_vs_load` | unique-payload goodput, same layout |
| `fig3_outage_length_crossover` | delay and retuning activity vs mean busy-run length — the crossover |
| `fig4_delay_cdf` | delay distribution at one operating point |
| `fig5_coblocked` | delay vs share of co-blocked time |
| `fig6_retune_cost` | delay vs retuning time |

## Limitations to state in the report

* Two links, one queue, one flow. No per-link traffic, no QoS classes, no
  aggregation, no multi-user contention inside a link.
* Binary capacity. A real link has a rate that depends on MCS and bandwidth, so
  "busy" would be better modelled as a reduced rate than as zero.
* Passive monitoring of both links is free. Active sounding would add cost and
  delay, which would weaken the switching rules.
* The ON/OFF channel is a two-state abstraction of OBSS traffic; run lengths
  are exponential or lognormal, not measured traces.
* Retuning is a fixed cost, whereas a real device would also lose beamforming
  and block-ack state, and would be subject to regulatory channel-switch time.
* This is MLO-inspired scheduling, not an IEEE 802.11be MAC implementation.
  No claim about a commercial AP is made.
