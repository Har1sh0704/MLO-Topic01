function chan = make_channel(cfg, seed)
%MAKE_CHANNEL  Generate the busy/idle state of both links for one replication.
%
%   chan = MAKE_CHANNEL(cfg, seed)  returns a 2 x cfg.T logical matrix,
%   chan(l,t) = true when link l is busy (unavailable to this device) at slot
%   t.
%
%   Model. Each link is a two-state ON/OFF process with exponentially
%   distributed run lengths (a Gilbert-Elliott process). This keeps the
%   "alternating busy and idle periods" of the brief but avoids the phase
%   locking of a purely periodic pattern: with fixed periods the two links
%   can stay perfectly in or out of phase, which is an artefact of the model
%   rather than a property of real OBSS interference.
%
%   With cfg.shared > 0 a fraction of the busy time is caused by a single
%   interferer heard on BOTH links. The common part is drawn once and OR-ed
%   into both links, so the marginal busy fraction stays exactly b(l):
%       b_own(l) = (b(l) - shared) / (1 - shared)
%   This is the knob that produces the "second link does not help" case.

T   = cfg.T;
b   = cfg.b(:).';
sh  = min(cfg.shared, min(b));

chan = false(2, T);

if sh > 0
    sharedTrace = onoff(T, sh, cfg.Rbar, seed * 7919 + 1, cfg.runCV);
    chan(1, :) = sharedTrace;
    chan(2, :) = sharedTrace;      % the same interferer on both links
end

for l = 1:2
    bOwn = (b(l) - sh) / max(1 - sh, eps);
    own  = onoff(T, bOwn, cfg.Rbar, seed * 7919 + 11 * l, cfg.runCV);
    chan(l, :) = chan(l, :) | own;
end
end

% -------------------------------------------------------------------------
function s = onoff(T, b, Rbar, seed, cv)
%ONOFF  Two-state process with busy fraction b, mean run 2*b*Rbar, and run
%       length coefficient of variation cv (1 = exponential = memoryless).
%       cv > 1 makes the congestion bursty: mostly short outages, but
%       occasionally a very long one - which is what a persistent OBSS
%       interferer looks like.
rs = RandStream('mt19937ar', 'Seed', seed);

if b <= 0
    s = false(1, T);  return
elseif b >= 1
    s = true(1, T);   return
end

Rbusy = max(1, 2 * b * Rbar);
Ridle = max(1, 2 * (1 - b) * Rbar);
pOn2Off = 1 / Rbusy;      % leave the busy state
pOff2On = 1 / Ridle;      % enter the busy state

if cv <= 0
    cv = 1;
end
sig2 = log(1 + cv^2);     % lognormal shape, mean-preserving

% Draw run lengths until the window is covered. Only a few hundred draws,
% far cheaper than a slot-by-slot loop.
lens   = zeros(1, 256);
states = zeros(1, 256);
nL   = 0;
tot  = 0;
st   = double(rand(rs) < b);       % start in the stationary distribution
while tot < T
    if cv == 1
        if st == 1
            L = max(1, ceil(-log(rand(rs)) / pOn2Off));
        else
            L = max(1, ceil(-log(rand(rs)) / pOff2On));
        end
    else
        if st == 1
            m = Rbusy;
        else
            m = Ridle;
        end
        L = max(1, ceil(exp(log(m) - sig2/2 + sqrt(sig2) * randn(rs))));
    end
    nL = nL + 1;
    if nL > numel(lens)
        lens   = [lens,   zeros(1, numel(lens))]; %#ok<AGROW>
        states = [states, zeros(1, numel(states))]; %#ok<AGROW>
    end
    lens(nL)   = L;
    states(nL) = st;
    tot = tot + L;
    st  = 1 - st;
end
lens   = lens(1:nL);
states = states(1:nL);

% Paint the runs onto the slot axis.
edges = [0, cumsum(lens)];
s = false(1, T);
for k = 1:nL
    a = edges(k) + 1;
    if a > T, break; end
    z = min(edges(k+1), T);
    if states(k) == 1
        s(a:z) = true;
    end
end
end
