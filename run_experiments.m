function run_experiments()
%RUN_EXPERIMENTS  Full experimental plan. Writes results.mat and CSV files.
%
%   Grid 1 (main):   5 congestion scenarios x 3 offered loads x 7 policies
%                    x 10 paired seeds
%   Grid 2 (sweep):  2 scenarios x 2 loads x 5 switching costs x 4 policies
%   Grid 3 (CDF):    delay distribution at one representative point
%   Grid 4 (corr):   MLO gain versus the fraction of co-blocked time
%
%   Inside one (scenario, load, seed) cell every policy sees the SAME arrival
%   trace and the SAME channel realisation: the comparison is paired, and the
%   confidence intervals are computed across seeds, not across packets.

t0 = tic;
here = fileparts(mfilename('fullpath'));
outDir = fullfile(here, 'results');
if ~exist(outDir, 'dir'), mkdir(outDir); end

cfg0 = default_cfg();
nSeed = cfg0.nSeeds;

%% ---- scenario definitions ----------------------------------------------
% b       : long-run busy fraction of each link
% shared  : fraction of the busy time caused by an interferer heard on both
%           links. shared = b makes the two links identical (negative case).
% runCV   : run-length coefficient of variation, 1 = memoryless, >1 = bursty
scen = struct('name', {}, 'b', {}, 'shared', {}, 'cv', {});
scen(1).name = 'A balanced';           scen(1).b = [0.20 0.20]; scen(1).shared = 0;    scen(1).cv = 1;
scen(2).name = 'B moderate imbalance'; scen(2).b = [0.10 0.60]; scen(2).shared = 0;    scen(2).cv = 1;
scen(3).name = 'C severe imbalance';   scen(3).b = [0.05 0.85]; scen(3).shared = 0;    scen(3).cv = 1;
scen(4).name = 'D co-blocked';         scen(4).b = [0.30 0.30]; scen(4).shared = 0.30; scen(4).cv = 1;
scen(5).name = 'E bursty balanced';    scen(5).b = [0.15 0.15]; scen(5).shared = 0;    scen(5).cv = 2.5;

loads = [0.20 0.50 0.80];
pols  = {'single_best','single_worst','rr','greedy','proposed','oracle','dual'};

nS = numel(scen); nL = numel(loads); nP = numel(pols);

%% ======================= grid 1: main ===================================
fprintf('Grid 1: %d scenarios x %d loads x %d policies x %d seeds = %d runs\n', ...
    nS, nL, nP, nSeed, nS*nL*nP*nSeed);

M = struct();   % raw per-seed metrics, each [nS nL nP nSeed]
flds = {'p95','p50','p99','mean','gp','u1','u2','swc','swl','drop'};
for k = 1:numel(flds), M.(flds{k}) = nan(nS,nL,nP,nSeed); end
badCons = 0;

for s = 1:nS
    cS = cfg0;
    cS.b = scen(s).b;
    cS.shared = scen(s).shared;
    cS.runCV  = scen(s).cv;
    C = sum(1 - cS.b);                 % combined capacity [pkt/slot]

    for sd = 1:nSeed
        ch = make_channel(cS, sd);     % same channel for all loads/policies
        for l = 1:nL
            lambda = loads(l) * C;
            arr = make_arrivals(cS, lambda, sd);
            for p = 1:nP
                c = cS;
                c.policy = pols{p};
                r = simulate_mlo(c, arr, ch);
                badCons = badCons + (~r.conserved);

                M.p95(s,l,p,sd)  = r.delayP95;
                M.p50(s,l,p,sd)  = r.delayP50;
                M.p99(s,l,p,sd)  = r.delayP99;
                M.mean(s,l,p,sd) = r.delayMean;
                M.gp(s,l,p,sd)   = r.goodput;
                M.u1(s,l,p,sd)   = r.util(1);
                M.u2(s,l,p,sd)   = r.util(2);
                M.swc(s,l,p,sd)  = r.swCount;
                M.swl(s,l,p,sd)  = r.swLostFrac;
                M.drop(s,l,p,sd) = r.dropRate;
            end
        end
    end
    fprintf('  %-22s done (%5.1f s)\n', scen(s).name, toc(t0));
end
if badCons > 0
    warning('run_experiments:conservation', ...
        '%d runs failed the packet-conservation check.', badCons);
end

AGG1 = aggregate(M, nS*nL*nP, nSeed);
EXP1 = struct('scen', {scen}, 'loads', {loads}, 'pols', {pols}, ...
    'raw', M, 'agg', AGG1, 'nSeed', nSeed);

%% ======================= grid 2: switching cost =========================
swds  = [0 1 2 4 8];
pols2 = {'rr','greedy','proposed','oracle'};
sIdx  = [1 2];
lIdx  = [2 3];
nW = numel(swds); nP2 = numel(pols2);

fprintf('Grid 2: %d scen x %d loads x %d switching costs x %d policies x %d seeds = %d runs\n', ...
    numel(sIdx), numel(lIdx), nW, nP2, nSeed, numel(sIdx)*numel(lIdx)*nW*nP2*nSeed);

M2 = struct();
flds2 = {'p95','gp','swl','swc'};
for k = 1:numel(flds2)
    M2.(flds2{k}) = nan(numel(sIdx),numel(lIdx),nW,nP2,nSeed);
end

for a = 1:numel(sIdx)
    s = sIdx(a);
    cS = cfg0;  cS.b = scen(s).b;  cS.shared = scen(s).shared;  cS.runCV = scen(s).cv;
    C = sum(1 - cS.b);
    for sd = 1:nSeed
        ch = make_channel(cS, sd);
        for b = 1:numel(lIdx)
            arr = make_arrivals(cS, loads(lIdx(b)) * C, sd);
            for w = 1:nW
                for q = 1:nP2
                    c = cS;
                    c.policy  = pols2{q};
                    c.swDelay = swds(w);
                    r = simulate_mlo(c, arr, ch);
                    M2.p95(a,b,w,q,sd) = r.delayP95;
                    M2.gp(a,b,w,q,sd)  = r.goodput;
                    M2.swl(a,b,w,q,sd) = r.swLostFrac;
                    M2.swc(a,b,w,q,sd) = r.swCount;
                end
            end
        end
    end
    fprintf('  %-22s done (%5.1f s)\n', scen(s).name, toc(t0));
end

AGG2 = aggregate(M2, numel(sIdx)*numel(lIdx)*nW*nP2, nSeed);
EXP2 = struct('scen', {scen}, 'loads', {loads}, 'swds', {swds}, ...
    'pols', {pols2}, 'sIdx', {sIdx}, 'lIdx', {lIdx}, ...
    'raw', M2, 'agg', AGG2, 'nSeed', nSeed);

%% ======================= grid 3: delay CDF ==============================
cdfPols = {'single_best','rr','greedy','proposed','dual'};
cdfS = 1;  cdfL = 2;      % balanced scenario, 50 % load
cS = cfg0;  cS.b = scen(cdfS).b;  cS.shared = scen(cdfS).shared;  cS.runCV = scen(cdfS).cv;
C = sum(1 - cS.b);
ch  = make_channel(cS, 1);
arr = make_arrivals(cS, loads(cdfL) * C, 1);
CDF = struct('pol', {}, 'd', {});
for p = 1:numel(cdfPols)
    c = cS;  c.policy = cdfPols{p};
    r = simulate_mlo(c, arr, ch);
    CDF(p).pol = cdfPols{p};
    CDF(p).d   = sort(r.delays);
end
fprintf('Grid 3 done (%5.1f s)\n', toc(t0));

%% ======================= grid 4: co-blocking sweep ======================
shVals = [0 0.10 0.20 0.30];
pols4  = {'single_best','greedy','proposed','dual'};
cS = cfg0;  cS.b = [0.30 0.30];  cS.runCV = 1;
C = sum(1 - cS.b);
nSh = numel(shVals); nP4 = numel(pols4);
M4 = struct();
M4.p95 = nan(nSh, nP4, nSeed);  M4.gp = nan(nSh, nP4, nSeed);
M4.swl = nan(nSh, nP4, nSeed);

for h = 1:nSh
    cH = cS;  cH.shared = shVals(h);
    for sd = 1:nSeed
        ch  = make_channel(cH, sd);
        arr = make_arrivals(cH, 0.5 * C, sd);
        for p = 1:nP4
            c = cH;  c.policy = pols4{p};
            r = simulate_mlo(c, arr, ch);
            M4.p95(h,p,sd) = r.delayP95;
            M4.gp(h,p,sd)  = r.goodput;
            M4.swl(h,p,sd) = r.swLostFrac;
        end
    end
end
AGG4 = aggregate(M4, nSh*nP4, nSeed);
EXP4 = struct('shVals', {shVals}, 'pols', {pols4}, 'raw', M4, 'agg', AGG4, 'nSeed', nSeed);
fprintf('Grid 4 done (%5.1f s)\n', toc(t0));

%% ======================= grid 5: outage-length sweep ===================
% The decisive experiment: how long must a busy period be, relative to the
% retuning time, before escaping to the other link pays off?
rbVals = [3 5 8 12 20 40 100];
pols5  = {'single_best','greedy','proposed','dual'};
ldVals = [0.2 0.5];
cS = cfg0;  cS.b = [0.30 0.30];  cS.shared = 0;  cS.runCV = 1;
C = sum(1 - cS.b);
nR = numel(rbVals); nP5 = numel(pols5); nLd = numel(ldVals);
M5 = struct();
cols = {'p95','gp','swc','swl'};
for k = 1:numel(cols)
    M5.(cols{k}) = nan(nLd, nR, nP5, nSeed);
end

for li = 1:nLd
    for ri = 1:nR
        cR = cS;  cR.Rbar = rbVals(ri);
        for sd = 1:nSeed
            ch  = make_channel(cR, sd);
            arr = make_arrivals(cR, ldVals(li) * C, sd);
            for p = 1:nP5
                c = cR;  c.policy = pols5{p};
                r = simulate_mlo(c, arr, ch);
                M5.p95(li,ri,p,sd) = r.delayP95;
                M5.gp(li,ri,p,sd)  = r.goodput;
                M5.swc(li,ri,p,sd) = r.swCount;
                M5.swl(li,ri,p,sd) = r.swLostFrac;
            end
        end
    end
end
AGG5 = aggregate(M5, nLd*nR*nP5, nSeed);
EXP5 = struct('rbVals', {rbVals}, 'ldVals', {ldVals}, 'pols', {pols5}, ...
    'raw', M5, 'agg', AGG5, 'nSeed', nSeed);
fprintf('Grid 5 done (%5.1f s)\n', toc(t0));

%% ======================= save ==========================================
save(fullfile(outDir, 'results.mat'), 'EXP1', 'EXP2', 'EXP4', 'EXP5', 'CDF', ...
    'scen', 'loads', 'pols', 'pols2', 'swds', 'cfg0');

writeLongCsv(fullfile(outDir, 'results_main.csv'), EXP1, ...
    {'p95','delayP95','slots'; 'p50','delayP50','slots'; 'p99','delayP99','slots';
     'mean','delayMean','slots'; 'gp','goodput','pkt/slot';
     'u1','utilisation_link1',''; 'u2','utilisation_link2','';
     'swc','switches','count'; 'swl','airtime_lost','frac';
     'drop','drop_rate','frac'});

writeSweepCsv(fullfile(outDir, 'results_swdelay.csv'), EXP2);
writeCsv4(fullfile(outDir, 'results_coblock.csv'), EXP4);
writeCsv5(fullfile(outDir, 'results_outage_length.csv'), EXP5, cfg0.swDelay);

fprintf('\nAll results written to %s  (%.1f s)\n', outDir, toc(t0));
end

% =========================================================================
function AGG = aggregate(M, nCells, nSeed)
%AGGREGATE  Mean and 95 % half-width over the last (seed) dimension.
f = fieldnames(M);
AGG = struct();
for k = 1:numel(f)
    x  = M.(f{k});
    sz = size(x);
    X  = reshape(x, nCells, nSeed);
    m  = mean(X, 2);
    h  = tcrit95(nSeed - 1) * std(X, 0, 2) / sqrt(nSeed);
    AGG.(f{k}) = struct('mean', reshape(m, sz(1:end-1)), ...
                        'ci',   reshape(h, sz(1:end-1)));
end
end

% =========================================================================
function writeLongCsv(fname, E, spec)
%WRITELONGCSV  One row per (scenario, load, policy, metric).
fid = fopen(fname, 'w');
fprintf(fid, 'scenario,load,policy,metric,unit,mean,ci95_halfwidth\n');
for s = 1:numel(E.scen)
    for l = 1:numel(E.loads)
        for p = 1:numel(E.pols)
            for k = 1:size(spec, 1)
                f = spec{k,1};
                if ~isfield(E.agg, f), continue; end
                m = E.agg.(f).mean(s,l,p);
                h = E.agg.(f).ci(s,l,p);
                fprintf(fid, '%s,%.2f,%s,%s,%s,%.6g,%.6g\n', ...
                    E.scen(s).name, E.loads(l), E.pols{p}, spec{k,2}, spec{k,3}, m, h);
            end
        end
    end
end
fclose(fid);
end

% =========================================================================
function writeSweepCsv(fname, E)
%WRITESWEEPCSV  Grid 2 has an extra dimension (switching cost).
fid = fopen(fname, 'w');
fprintf(fid, 'scenario,load,swdelay,policy,metric,unit,mean,ci95_halfwidth\n');
spec = {'p95','delayP95','slots'; 'gp','goodput','pkt/slot';
        'swl','airtime_lost','frac'; 'swc','switches','count'};
for a = 1:numel(E.sIdx)
    s = E.sIdx(a);
    for b = 1:numel(E.lIdx)
        l = E.lIdx(b);
        for w = 1:numel(E.swds)
            for p = 1:numel(E.pols)
                for k = 1:size(spec, 1)
                    m = E.agg.(spec{k,1}).mean(a,b,w,p);
                    h = E.agg.(spec{k,1}).ci(a,b,w,p);
                    fprintf(fid, '%s,%.2f,%d,%s,%s,%s,%.6g,%.6g\n', ...
                        E.scen(s).name, E.loads(l), E.swds(w), E.pols{p}, ...
                        spec{k,2}, spec{k,3}, m, h);
                end
            end
        end
    end
end
fclose(fid);
end

% =========================================================================
function writeCsv5(fname, E, swD)
fid = fopen(fname, 'w');
fprintf(fid, 'load,mean_busy_run_slots,retune_slots,policy,metric,mean,ci95_halfwidth\n');
spec = {'p95','delayP95'; 'gp','goodput'; 'swc','switches'; 'swl','airtime_lost'};
for li = 1:numel(E.ldVals)
    for ri = 1:numel(E.rbVals)
        mbr = 2 * 0.30 * E.rbVals(ri);      % mean busy run of the busy state
        for p = 1:numel(E.pols)
            for k = 1:size(spec, 1)
                m = E.agg.(spec{k,1}).mean(li,ri,p);
                w = E.agg.(spec{k,1}).ci(li,ri,p);
                fprintf(fid, '%.2f,%.1f,%d,%s,%s,%.6g,%.6g\n', E.ldVals(li), ...
                    mbr, swD, E.pols{p}, spec{k,2}, m, w);
            end
        end
    end
end
fclose(fid);
end

% =========================================================================
function writeCsv4(fname, E)
fid = fopen(fname, 'w');
fprintf(fid, 'shared_fraction,policy,metric,mean,ci95_halfwidth\n');
spec = {'p95','delayP95'; 'gp','goodput'; 'swl','airtime_lost'};
for h = 1:numel(E.shVals)
    for p = 1:numel(E.pols)
        for k = 1:size(spec, 1)
            m = E.agg.(spec{k,1}).mean(h,p);
            w = E.agg.(spec{k,1}).ci(h,p);
            fprintf(fid, '%.2f,%s,%s,%.6g,%.6g\n', E.shVals(h), E.pols{p}, ...
                spec{k,2}, m, w);
        end
    end
end
fclose(fid);
end
