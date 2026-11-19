function out = simulate_mlo(cfg, arrivals, chan)
%SIMULATE_MLO  One replication of the two-link MLO packet-queue model.
%
%   out = SIMULATE_MLO(cfg, arrivals, chan)
%
%   cfg       parameter struct, see default_cfg.m
%   arrivals  1 x cfg.T Poisson arrival counts, from make_arrivals.m
%   chan      2 x cfg.T logical busy state, from make_channel.m
%
%   Both inputs are generated OUTSIDE this function and reused for every
%   policy of the same (scenario, load, seed) triple, which is what makes the
%   policy comparison *paired*: identical packet arrivals and identical
%   channel, only the control decision differs.
%
%   Stated abstractions (repeated in the report):
%     * one traffic queue shared by both links;
%     * a link carries at most one packet per slot and only when idle;
%       capacity is binary (1 or 0 packets per slot), no collisions, no
%       retransmission, no aggregation, no rate adaptation;
%     * one transmit chain: using one link excludes the other, and changing
%       link costs cfg.swDelay slots of airtime;
%     * finite buffer of cfg.Qcap packets, drop-tail on overflow;
%     * passive CCA monitoring of both links is available even while
%       transmitting on one of them (multi-RF front end, single TX chain).
%       Monitoring is free; retuning is not.
%
%   Policies
%     'single_best'  static association to the less congested link
%     'single_worst' static association to the more congested link
%     'rr'           round robin, fixed dwell per link (blind MLO)
%     'greedy'       switch whenever the other link is idle (state-aware,
%                    no cost and no backlog test) - ablation baseline
%     'proposed'     queue + busy-time rule, estimated online
%     'oracle'       same rule with the true busy fraction and run length
%     'dual'         two radios, both links usable per slot (hardware bound)

T    = cfg.T;
warm = cfg.warmup;
b    = cfg.b(:).';
swD  = cfg.swDelay;
cap  = cfg.Qcap;

%% ---- circular arrival-time buffer --------------------------------------
qt   = zeros(1, cap);
head = 1;  tail = 1;  qlen = 0;

%% ---- state -------------------------------------------------------------
cur     = 0;      % link currently tuned (0 = not yet attached)
swRem   = 0;      % remaining retune slots
% Two counter sets: "all" feeds the conservation check, "W" the measurement
% window after warm-up. Mixing them would inflate goodput.
served  = 0;  servedW = 0;
dropped = 0;  droppedW = 0;
nArr    = 0;  nArrW = 0;
tx      = [0 0];  txW = [0 0];
swCnt   = 0;  swCntW = 0;
swLost  = 0;  swLostW = 0;
delays  = zeros(1, 2*T + 8);
nd      = 0;

% online estimators (proposed rule)
estP    = [0.5 0.5];    % EWMA of P(link busy)
estRun  = [cfg.Rbar cfg.Rbar];  % EWMA of busy-run length [slots]
runLen  = [0 0];        % consecutive busy slots observed right now
alphaP   = 1 / max(cfg.measWin, 1);
alphaRun = 1 / 16;

% history of the last NH completed busy runs per link. A conditional mean
% over this history is what lets the rule tell a short outage from the start
% of a long one - the thing a plain "is it busy?" test cannot do.
NH      = 64;
runHist = zeros(2, NH);
histN   = [0 0];
histI   = [1 1];

%% ---- policy code (integer switch is much faster than strcmp in the loop)
switch lower(cfg.policy)
    case 'single_best',  polId = 1;
    case 'single_worst', polId = 2;
    case 'rr',           polId = 3;
    case 'proposed',     polId = 4;
    case 'oracle',       polId = 5;
    case 'dual',         polId = 6;
    case 'greedy',       polId = 7;
    otherwise, error('simulate_mlo:policy', 'Unknown policy "%s".', cfg.policy);
end
if cfg.dualRadio, polId = 6; end

if polId == 1
    [~, cur] = min(b);          % static, chosen at association
elseif polId == 2
    [~, cur] = max(b);
elseif polId == 3
    cur = 1;                    % round robin starts on link 1
end

qmin  = max(2, swD);            % backlog needed to justify a retune
mslot = max(2, round(swD / 2)); % hysteresis margin on the residual test

%% ======================= main loop ======================================
for t = 1:T

    % ---- channel state from the pre-generated busy/idle traces -----------
    busy1 = chan(1, t);
    busy2 = chan(2, t);

    % ---- passive monitoring of both links -------------------------------
    if busy1
        runLen(1) = runLen(1) + 1;
    elseif runLen(1) > 0
        estRun(1) = estRun(1) + alphaRun * (runLen(1) - estRun(1));
        runHist(1, histI(1)) = runLen(1);
        histI(1) = mod(histI(1), NH) + 1;
        histN(1) = min(histN(1) + 1, NH);
        runLen(1) = 0;
    end
    if busy2
        runLen(2) = runLen(2) + 1;
    elseif runLen(2) > 0
        estRun(2) = estRun(2) + alphaRun * (runLen(2) - estRun(2));
        runHist(2, histI(2)) = runLen(2);
        histI(2) = mod(histI(2), NH) + 1;
        histN(2) = min(histN(2) + 1, NH);
        runLen(2) = 0;
    end
    estP(1) = estP(1) + alphaP * (busy1 - estP(1));
    estP(2) = estP(2) + alphaP * (busy2 - estP(2));

    % ---- arrivals --------------------------------------------------------
    inWin = t > warm;
    n = arrivals(t);
    if n > 0
        nArr = nArr + n;
        if inWin, nArrW = nArrW + n; end
        for k = 1:n
            if qlen < cap
                qt(tail) = t;
                tail = tail + 1;
                if tail > cap, tail = 1; end
                qlen = qlen + 1;
            else
                dropped = dropped + 1;   % buffer full -> drop-tail
                if inWin, droppedW = droppedW + 1; end
            end
        end
    end

    % ---- two-radio reference: each idle link serves one packet -----------
    if polId == 6
        if qlen > 0 && ~busy1
            a = qt(head); head = head + 1; if head > cap, head = 1; end
            qlen = qlen - 1; served = served + 1; tx(1) = tx(1) + 1;
            if inWin
                servedW = servedW + 1; txW(1) = txW(1) + 1;
                nd = nd + 1; delays(nd) = t - a + 1;  % arrival -> end of its TX slot
            end
        end
        if qlen > 0 && ~busy2
            a = qt(head); head = head + 1; if head > cap, head = 1; end
            qlen = qlen - 1; served = served + 1; tx(2) = tx(2) + 1;
            if inWin
                servedW = servedW + 1; txW(2) = txW(2) + 1;
                nd = nd + 1; delays(nd) = t - a + 1;  % arrival -> end of its TX slot
            end
        end
        continue
    end

    % ---- retuning in progress: the radio is unavailable ------------------
    if swRem > 0
        swRem  = swRem - 1;
        swLost = swLost + 1;
        if inWin, swLostW = swLostW + 1; end
        continue
    end

    % ---- nothing to send -------------------------------------------------
    if qlen == 0
        continue
    end

    if cur == 0
        [~, cur] = min(estP);       % attach at first packet, no cost
    end
    alt = 3 - cur;
    busyCur = (cur == 1) && busy1 || (cur == 2) && busy2;

    % ---- link-selection decision ----------------------------------------
    doSwitch = false;
    switch polId
        case 3      % round robin with a fixed dwell: blind to the channel
            if mod(t - 1, cfg.rrDwell) == 0 && t > 1
                doSwitch = true;
            end
        case 7      % greedy: escape whenever the other link looks idle
            doSwitch = busyCur && (alt == 1 && ~busy1 || alt == 2 && ~busy2);
        case {4, 5} % proposed rule (4 estimated online, 5 oracle)
            if busyCur
                altIdle = (alt == 1) && ~busy1 || (alt == 2) && ~busy2;
                if altIdle
                    if polId == 4
                        pB = estP;  means = estRun;
                    else
                        pB = b;     means = 2 * b * cfg.Rbar;
                    end

                    % (a) structurally better link: move if the long-run
                    %     availability gain pays for the retune over a
                    %     horizon that lengthens with the backlog
                    mu   = 1 - pB;
                    gain = mu(alt) - mu(cur);
                    H    = cfg.H0 * (1 + min(qlen, cfg.Qthr) / cfg.Qthr);
                    need = swD / max(H, 1) + cfg.margin;
                    doSwitch = gain > need;

                    % (b) escape the outage only once it has lasted at least
                    %     one retune time. A link that has been blocked for a
                    %     single slot is likely to clear, and a naive "other
                    %     link is idle, move now" rule pays the retune for
                    %     nothing. This is the busy-time part of the rule.
                    if ~doSwitch && runLen(cur) >= swD
                        k = runLen(cur);
                        if polId == 4
                            % conditional mean remaining outage given that
                            % the current outage already exceeds k slots,
                            % from the last NH completed outages
                            h = runHist(cur, 1:histN(cur));
                            sel = h(h > k);
                            if isempty(sel)
                                base = means(cur);
                            else
                                base = mean(sel);
                            end
                        else
                            base = means(cur);
                        end
                        resid = max(0, base - k);
                        % deep backlog => airtime-limited, so the retune has
                        % to pay for the return trip as well
                        if qlen >= cfg.Qthr
                            needResid = 2 * swD + mslot;
                        else
                            needResid = swD + mslot;
                        end
                        doSwitch = resid > needResid;
                    end
                end
            end
    end

    if doSwitch
        swCnt = swCnt + 1;
        cur   = alt;
        if inWin, swCntW = swCntW + 1; end
        if swD > 0
            swRem  = swD - 1;    % the current slot is the first lost slot
            swLost = swLost + 1;
            if inWin, swLostW = swLostW + 1; end
            continue
        end
        % zero retuning cost: the new link must still be idle to transmit
        busyCur = (cur == 1) && busy1 || (cur == 2) && busy2;
    end

    % ---- transmit if the tuned link is idle ------------------------------
    if ~busyCur || doSwitch
        a = qt(head); head = head + 1; if head > cap, head = 1; end
        qlen = qlen - 1;
        served = served + 1;
        tx(cur) = tx(cur) + 1;
        if inWin
            servedW = servedW + 1;
            txW(cur) = txW(cur) + 1;
            nd = nd + 1; delays(nd) = t - a + 1;  % arrival -> end of its TX slot
        end
    end
end

%% ======================= metrics ========================================
Teff = T - warm;
d    = delays(1:nd);

out = struct();
out.policy     = cfg.policy;
out.nArrivals  = nArr;
out.served     = served;
out.dropped    = dropped;
out.qlenEnd    = qlen;
% conservation: every packet is served, dropped, or still in the buffer
out.conserved  = (nArr == served + dropped + qlen);
out.goodput    = servedW / Teff;               % unique payload pkts/slot
out.util       = txW / Teff;                   % per-link utilisation
out.swCount    = swCntW;
out.swLostFrac = swLostW / Teff;               % airtime wasted on retuning
out.dropRate   = droppedW / max(nArrW, 1);
out.nDelivered = nd;

if nd > 0
    out.delayMean = mean(d);
    out.delayP50  = prctile_b(d, 50);
    out.delayP95  = prctile_b(d, 95);
    out.delayP99  = prctile_b(d, 99);
else
    out.delayMean = NaN; out.delayP50 = NaN;
    out.delayP95  = NaN; out.delayP99 = NaN;
end

out.delays = d;    % kept for the delay-CDF figure; cleared by the caller
end
