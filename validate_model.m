function validate_model()
%VALIDATE_MODEL  Known-answer and conservation checks for the simulator.
%
%   Validation guide step 4: "verify a case with a known answer: no noise,
%   no loss, one user, zero overhead, or constant traffic. Check conservation
%   of packets, bytes, airtime and energy."
%
%   Run this BEFORE looking at any policy result. If a test fails, no number
%   produced by the simulator should be trusted.
%
%   Reference result: M/D/1 mean sojourn time  E[T] = 1 + rho/(2(1-rho))
%   (deterministic 1-slot service, Poisson arrivals, FCFS, infinite buffer).

fprintf('\n================ MODEL VALIDATION ================\n');
P = 0; F = 0;

base = default_cfg();
base.T       = 400000;
base.warmup  = 20000;
base.Qcap    = 200000;     % effectively infinite: drops cannot mask errors
base.swDelay = 0;
base.dualRadio = false;

%% --- 1. M/D/1 mean delay, single clear link, two loads -------------------
for rho = [0.5 0.8]
    c = base;  c.b = [0 0];  c.policy = 'single_best';
    a = make_arrivals(c, rho, 7);
    ch = make_channel(c, 7);
    r = simulate_mlo(c, a, ch);
    ref = 1 + rho / (2 * (1 - rho));
    err = abs(r.delayMean - ref) / ref;
    [P, F] = report(sprintf('M/D/1 mean delay, rho = %.1f', rho), ...
        r.delayMean, ref, err * 100, '%', err < 0.05, P, F);
end

%% --- 2. Arrival-rate estimator ------------------------------------------
c = base;  c.b = [0 0];  c.policy = 'single_best';
a = make_arrivals(c, 0.5, 11);
rhoHat = sum(a(c.warmup+1:end)) / (c.T - c.warmup);
[P, F] = report('arrival rate, target 0.500', rhoHat, 0.5, 0, '', ...
    abs(rhoHat - 0.5) < 0.01, P, F);

%% --- 3. Packet conservation, every policy -------------------------------
pols = {'single_best','single_worst','rr','greedy','proposed','oracle','dual'};
allOk = true;
for k = 1:numel(pols)
    c = base;  c.b = [0.10 0.60];  c.policy = pols{k};
    c.T = 60000;  c.warmup = 5000;  c.Qcap = 600;  c.swDelay = 4;
    a  = make_arrivals(c, 1.0, 3);
    ch = make_channel(c, 3);
    r  = simulate_mlo(c, a, ch);
    allOk = allOk && r.conserved;
end
[P, F] = report('packet conservation, all 7 policies', double(allOk), 1, 0, '', ...
    allOk, P, F);

%% --- 4. Saturation: offered load 1.2, capacity 1 pkt/slot ----------------
c = base;  c.b = [0 0];  c.policy = 'single_best';  c.Qcap = 600;
a  = make_arrivals(c, 1.2, 5);
ch = make_channel(c, 5);
r  = simulate_mlo(c, a, ch);
% 0.2 of the 1.2 offered packets/slot cannot be carried and must be dropped
okDrop = r.dropRate > 0.12 && r.dropRate < 0.22;
[P, F] = report('overload goodput, capacity 1.0 pkt/slot', r.goodput, 1.0, ...
    abs(r.goodput-1)*100, '%', abs(r.goodput-1) < 0.02 && okDrop, P, F);

%% --- 5. Utilisation with no retuning and one link used -------------------
c = base;  c.b = [0 0];  c.policy = 'single_best';  c.Qcap = 200000;
a  = make_arrivals(c, 0.5, 9);
ch = make_channel(c, 9);
r  = simulate_mlo(c, a, ch);
[P, F] = report('link-1 utilisation at rho = 0.5', r.util(1), 0.5, 0, '', ...
    abs(r.util(1) - 0.5) < 0.01 && r.util(2) == 0, P, F);

%% --- 6. Busy fraction realised by the channel model ---------------------
c = base;  c.b = [0.05 0.85];  c.T = 400000;
ch = make_channel(c, 21);
b1 = mean(ch(1,:));  b2 = mean(ch(2,:));
[P, F] = report('realised busy fraction, link 2 (0.85)', b2, 0.85, ...
    (b2-0.85)*100, '', abs(b1-0.05) < 0.01 && abs(b2-0.85) < 0.01, P, F);

%% --- 7. A second radio really doubles the capacity ----------------------
c = base;  c.b = [0 0];  c.policy = 'dual';  c.Qcap = 600;
a  = make_arrivals(c, 1.5, 4);
ch = make_channel(c, 4);
r  = simulate_mlo(c, a, ch);
[P, F] = report('dual-radio goodput at load 1.5', r.goodput, 1.5, ...
    abs(r.goodput-1.5)/1.5*100, '%', r.dropRate < 0.02 && r.goodput > 1.45, P, F);

%% --- 8. Round robin is balanced when the links are identical ------------
c = base;  c.b = [0 0];  c.policy = 'rr';  c.swDelay = 0;  c.Qcap = 200000;
a  = make_arrivals(c, 0.5, 6);
ch = make_channel(c, 6);
r  = simulate_mlo(c, a, ch);
[P, F] = report('RR splits identical links (0.25 / 0.25)', r.util(1), 0.25, 0, '', ...
    abs(r.util(1) - r.util(2)) < 0.02 && abs(r.goodput - 0.5) < 0.01, P, F);

%% --- 9. Retuning really costs exactly swDelay slots ---------------------
% Packet 1 at t = 1 attaches the radio to link 1 and is served at once.
% Packet 2 at t = 20 arrives just as link 1 blocks, so the policy must
% retune, and its extra delay must be exactly swDelay slots - no more
% (off-by-one in the countdown) and no less.
c = base;  c.policy = 'greedy';
c.T = 200;  c.warmup = 0;  c.Qcap = 10;  c.b = [0 0];
a  = zeros(1, c.T);  a(1) = 1;  a(20) = 1;
ch = false(2, c.T);  ch(1, 20:end) = true;   % link 1 blocks, link 2 clear

d = zeros(1, 2);
sw = [0 5];
for k = 1:2
    cc = c;  cc.swDelay = sw(k);
    r  = simulate_mlo(cc, a, ch);
    d(k) = r.delays(2) - r.delays(1);
end
[P, F] = report('forced retune costs exactly swDelay = 5', d(2), 5, 0, '', ...
    d(1) == 0 && d(2) == 5, P, F);

fprintf('--------------------------------------------------\n');
fprintf('  PASSED %d   FAILED %d\n', P, F);
fprintf('==================================================\n\n');
if F > 0
    warning('validate_model:fail', ...
        '%d validation test(s) failed - do not trust the policy results.', F);
end
end

% -------------------------------------------------------------------------
function [P, F] = report(name, got, want, pctErr, unit, ok, P, F)
if ok
    tag = 'PASS'; P = P + 1;
else
    tag = 'FAIL'; F = F + 1;
end
if isempty(unit)
    extra = '';
else
    extra = sprintf(' (%+.3f%%)', pctErr);
end
fprintf('  [%s] %-44s got %9.4f  target %9.4f%s\n', tag, name, got, want, extra);
end
