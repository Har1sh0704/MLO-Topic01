function plot_figures()
%PLOT_FIGURES  Publication figures from results/results.mat.
%
%   Writes PNG (300 dpi) and vector PDF into figs/.

here   = fileparts(mfilename('fullpath'));
figDir = fullfile(here, 'figs');
if ~exist(figDir, 'dir'), mkdir(figDir); end
load(fullfile(here, 'results', 'results.mat'));

set(0, 'DefaultAxesFontName', 'Helvetica', ...
       'DefaultAxesFontSize', 10, ...
       'DefaultAxesLineWidth', 0.8, ...
       'DefaultAxesTickDir', 'out', ...
       'DefaultLineLineWidth', 1.3, ...
       'DefaultFigureColor', 'w');

sty = style_map();
Teff = cfg0.T - cfg0.warmup;

% series shown on the load plots (oracle is left to the crossover figure)
pickLoad = {'single_best','single_worst','rr','greedy','proposed','dual'};

%% ================= F1: 95th-percentile delay vs load ===================
show = [1 2 3 5];
fig = figure('Position', [60 60 900 740]);
tiledlayout(2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
for k = 1:numel(show)
    s = show(k);
    nexttile; hold on;
    for q = 1:numel(pickLoad)
        p = find(strcmp(EXP1.pols, pickLoad{q}));
        y = squeeze(EXP1.agg.p95.mean(s, :, p)).';
        e = squeeze(EXP1.agg.p95.ci(s, :, p)).';
        draw_ci(EXP1.loads * 100, y, e, sty, pickLoad{q});
    end
    hold off;
    set(gca, 'YScale', 'log');
    xlabel('Offered load (% of combined capacity)');
    ylabel('95th-percentile delay (slots)');
    title(sprintf('(%s) %s', char('a' + k - 1), EXP1.scen(s).name), ...
        'FontWeight', 'normal');
    xticks(EXP1.loads * 100); xlim([15 85]); ylim([1 3e4]);
    yticks(10.^(0:4));
    grid on;
    if k == 1, ax1 = gca; end
end
lgd = legend(ax1, 'Orientation', 'horizontal', 'NumColumns', 3);
lgd.Layout.Tile = 'south'; lgd.FontSize = 8; lgd.Box = 'off';
save_fig(fig, figDir, 'fig1_delay_vs_load');

%% ================= F2: goodput vs load =================================
fig = figure('Position', [60 60 900 740]);
tiledlayout(2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
for k = 1:numel(show)
    s = show(k);
    nexttile; hold on;
    for q = 1:numel(pickLoad)
        p = find(strcmp(EXP1.pols, pickLoad{q}));
        y = squeeze(EXP1.agg.gp.mean(s, :, p)).';
        e = squeeze(EXP1.agg.gp.ci(s, :, p)).';
        draw_ci(EXP1.loads * 100, y, e, sty, pickLoad{q});
    end
    hold off;
    xlabel('Offered load (% of combined capacity)');
    ylabel('Goodput (packets/slot)');
    title(sprintf('(%s) %s', char('a' + k - 1), EXP1.scen(s).name), ...
        'FontWeight', 'normal');
    xticks(EXP1.loads * 100); xlim([15 85]);
    grid on;
    if k == 1, ax1 = gca; end
end
lgd = legend(ax1, 'Orientation', 'horizontal', 'NumColumns', 3);
lgd.Layout.Tile = 'south'; lgd.FontSize = 8; lgd.Box = 'off';
save_fig(fig, figDir, 'fig2_goodput_vs_load');

%% ================= F3: the decisive crossover ==========================
% Left: delay against the persistence of the congestion, with the retuning
% time marked. Right: how often each rule actually retunes.
fig = figure('Position', [80 80 980 400]);
tiledlayout(1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
mbr = 2 * 0.30 * EXP5.rbVals;
lbl = arrayfun(@(v) sprintf('%g', round(v*10)/10), mbr, 'UniformOutput', false);

nexttile; hold on;
for q = 1:numel(EXP5.pols)
    y = squeeze(EXP5.agg.p95.mean(1, :, q)).';
    e = squeeze(EXP5.agg.p95.ci(1, :, q)).';
    draw_ci(mbr, y, e, sty, EXP5.pols{q});
end
xline(cfg0.swDelay, ':', 'Color', [0.35 0.35 0.35], 'HandleVisibility', 'off');
hold off;
set(gca, 'XScale', 'log');
xticks(mbr); xticklabels(lbl);
xlabel('Mean busy-run length (slots)');
ylabel('95th-percentile delay (slots)');
title(sprintf('Delay, offered load %d%%', round(EXP5.ldVals(1)*100)), ...
    'FontWeight', 'normal');
grid on; xlim([min(mbr)*0.85 max(mbr)*1.15]);
legend('Location', 'north', 'FontSize', 8);

nexttile; hold on;
for q = 1:numel(EXP5.pols)
    r = squeeze(EXP5.agg.swc.mean(1, :, q)).' / Teff * 1000;
    y = squeeze(EXP5.agg.p95.mean(1, :, q)).';  %#ok<NASGU>
    s = sty.(EXP5.pols{q});
    semilogx(mbr, r, 'Color', s.c, 'LineStyle', s.s, 'Marker', 'o', ...
        'MarkerSize', 4, 'MarkerFaceColor', 'w', 'DisplayName', s.name);
end
xline(cfg0.swDelay, ':', 'Color', [0.35 0.35 0.35], 'HandleVisibility', 'off');
hold off;
set(gca, 'XScale', 'log');
xticks(mbr); xticklabels(lbl);
xlabel('Mean busy-run length (slots)');
ylabel('Retunes per 1000 slots');
title('Retuning activity', 'FontWeight', 'normal');
grid on; xlim([min(mbr)*0.85 max(mbr)*1.15]);
save_fig(fig, figDir, 'fig3_outage_length_crossover');

%% ================= F4: delay CDF =======================================
fig = figure('Position', [80 80 620 500]); hold on;
for k = 1:numel(CDF)
    d = CDF(k).d;
    if isempty(d), continue; end
    f = (1:numel(d))' / numel(d);
    s = sty.(CDF(k).pol);
    plot(d, f, 'Color', s.c, 'LineStyle', s.s, 'DisplayName', s.name);
end
hold off;
set(gca, 'XScale', 'log');
xlim([1 1000]); xticks([1 2 5 10 20 50 100 200 500 1000]);
xlabel('Packet delay (slots, log scale)'); ylabel('Empirical CDF');
title(sprintf('Delay distribution: %s, load %d%%', EXP1.scen(1).name, ...
    round(EXP1.loads(2) * 100)), 'FontWeight', 'normal');
grid on; ylim([0 1]);
lgd = legend('Orientation', 'horizontal', 'NumColumns', 3);
lgd.Location = 'southoutside'; lgd.Box = 'off';
save_fig(fig, figDir, 'fig4_delay_cdf');

%% ================= F5: co-blocking kills the gain ======================
fig = figure('Position', [80 80 640 440]); hold on;
for q = 1:numel(EXP4.pols)
    y = squeeze(EXP4.agg.p95.mean(:, q));
    e = squeeze(EXP4.agg.p95.ci(:, q));
    draw_ci(EXP4.shVals * 100, y, e, sty, EXP4.pols{q});
end
hold off;
xlabel('Busy time caused by the same interferer on both links (%)');
ylabel('95th-percentile delay (slots)');
title('Delay when the two links are congested together', 'FontWeight', 'normal');
grid on; legend('Location', 'northwest'); xlim([-1 31]);
save_fig(fig, figDir, 'fig5_coblocked');

%% ================= F6: retuning cost ===================================
fig = figure('Position', [60 60 900 470]);
tiledlayout(1, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
cases = [1 1; 2 1];      % (scenario index, load index inside the sweep)
for k = 1:2
    a = cases(k, 1);  l = cases(k, 2);
    nexttile; hold on;
    for q = 1:numel(EXP2.pols)
        y = squeeze(EXP2.agg.p95.mean(a, l, :, q)).';
        e = squeeze(EXP2.agg.p95.ci(a, l, :, q)).';
        draw_ci(EXP2.swds, y, e, sty, EXP2.pols{q});
    end
    hold off;
    set(gca, 'YScale', 'log');
    xlabel('Retuning time per switch (slots)');
    ylabel('95th-percentile delay (slots)');
    title(sprintf('%s, load %d%%', EXP2.scen(EXP2.sIdx(a)).name, ...
        round(EXP2.loads(EXP2.lIdx(l)) * 100)), 'FontWeight', 'normal');
    grid on; xticks(EXP2.swds);
    if k == 1, ax1 = gca; end
end
lgd = legend(ax1, 'Orientation', 'horizontal', 'NumColumns', 4);
lgd.Layout.Tile = 'south'; lgd.FontSize = 8; lgd.Box = 'off';
save_fig(fig, figDir, 'fig6_retune_cost');

fprintf('Figures written to %s\n', figDir);
end

% =========================================================================
function sty = style_map()
sty.single_best  = mk([0.25 0.25 0.25], '-',  'Single link');
sty.single_worst = mk([0.62 0.62 0.62], '-',  'Single link, worse band');
sty.rr           = mk([0.90 0.45 0.05], '--', 'Round robin');
sty.greedy       = mk([0.20 0.55 0.85], '-',  'Greedy switch');
sty.proposed     = mk([0.75 0.10 0.15], '-',  'Proposed rule');
sty.oracle       = mk([0.45 0.20 0.65], ':',  'Oracle statistics');
sty.dual         = mk([0.10 0.60 0.35], '-',  'Dual radio (bound)');
end

function s = mk(c, l, n)
s = struct('c', c, 's', l, 'name', n);
end

% =========================================================================
function draw_ci(x, y, e, sty, name)
s = sty.(name);
if strcmp(s.s, ':')
    errorbar(x, y, e, 'Color', s.c, 'LineStyle', s.s, 'Marker', 'none', ...
        'CapSize', 3, 'DisplayName', s.name);
else
    errorbar(x, y, e, 'Color', s.c, 'LineStyle', s.s, 'Marker', 'o', ...
        'MarkerSize', 4, 'MarkerFaceColor', 'w', 'CapSize', 3, ...
        'DisplayName', s.name);
end
end

% =========================================================================
function save_fig(fig, dir, name)
exportgraphics(fig, fullfile(dir, [name '.png']), 'Resolution', 300);
exportgraphics(fig, fullfile(dir, [name '.pdf']), 'ContentType', 'vector');
end
