function cfg = default_cfg()
%DEFAULT_CFG  Single source of truth for every parameter of the MLO model.
%
%   Every value is tagged
%     (M) measured / taken from a cited source or a standard
%     (I) illustrative, chosen to expose the effect; swept where it matters
%
%   Time unit: one slot = one transmission opportunity on a link. We take the
%   IEEE 802.11 OFDMA time-unit granularity of ~1 ms, so delays below are in
%   units of ~ms.

cfg = struct();

%% ---- run length and statistics -----------------------------------------
cfg.T        = 60000;   % (I) slots simulated per replication
cfg.warmup   = 10000;   % (I) slots discarded before any statistic is taken
cfg.nSeeds   = 10;      % (I) independent replications per grid point

%% ---- channel / congestion process --------------------------------------
% Each link alternates busy (a foreign OBSS occupies the channel and CCA
% reports busy) and idle periods. Busy runs and idle runs are independent
% exponential random variables, i.e. a two-state ON/OFF (Gilbert-Elliott)
% process with
%       E[busy run] = 2*b*Rbar,  E[idle run] = 2*(1-b)*Rbar,
% so that the long-run busy fraction is exactly b.
cfg.b        = [0.10 0.60];   % (I) default busy fractions, swept below
cfg.Rbar     = 100;           % (I) reference half-cycle length [slots]
cfg.runCV    = 1;             % (I) coefficient of variation of the run
                              %     lengths. 1 = exponential (memoryless).
                              %     >1 = bursty congestion: mostly short
                              %     outages plus rare very long ones.
cfg.shared   = 0;             % (I) fraction of time blocked by a COMMON
                              %     interferer seen by both links (0 = the
                              %     two links are independently congested)

%% ---- device / MAC model ------------------------------------------------
cfg.swDelay  = 4;       % (I) retune cost: slots of airtime lost per switch
cfg.Qcap     = 600;     % (I) finite buffer [packets]; overflow is dropped
cfg.rrDwell  = 50;      % (I) dwell time per link for round-robin [slots]
cfg.dualRadio = false;  % true -> two independent radios, no retune

%% ---- proposed policy knobs --------------------------------------------
cfg.measWin  = 64;      % (I) EWMA window for passive busy estimation [slots]
cfg.H0       = 200;     % (I) base amortisation horizon [slots]
cfg.Qthr     = 20;      % (I) backlog level at which the horizon doubles [pkt]
cfg.margin   = 0.03;    % (I) hysteresis on estimated availability

%% ---- default policy ----------------------------------------------------
cfg.policy   = 'proposed';

end
