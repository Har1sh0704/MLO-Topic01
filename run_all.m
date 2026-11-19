function run_all()
%RUN_ALL  One-command reproduction of every number and figure in the report.
%
%     run_all
%
%   It (1) validates the simulator against known answers, (2) runs the four
%   experiment grids, (3) draws the figures. Runtime is well under a minute on
%   a laptop: no toolbox beyond base MATLAB is required.
%
%   Outputs
%     results/results.mat          every per-seed metric and its 95% CI
%     results/results_main.csv     main grid, long format
%     results/results_swdelay.csv  retuning-cost sweep
%     results/results_coblock.csv  co-blocking sweep
%     results/results_outage_length.csv  outage-persistence sweep
%     figs/fig1..fig6 .png / .pdf

here = fileparts(mfilename('fullpath'));
addpath(here);

fprintf('\n### 1/3  validating the model\n');
validate_model();

fprintf('### 2/3  running the experiment grids\n');
run_experiments();

fprintf('### 3/3  drawing figures\n');
plot_figures();

fprintf('\nDone. See results/ and figs/.\n');
end
