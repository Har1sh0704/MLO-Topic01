function arrivals = make_arrivals(cfg, lambda, seed)
%MAKE_ARRIVALS  Poisson packet arrivals for one replication.
%
%   arrivals = MAKE_ARRIVALS(cfg, lambda, seed) is a 1 x cfg.T vector of
%   arrival counts, lambda packets per slot.
%
%   The arrivals do not depend on the policy, so the same vector is reused
%   for every policy of a given (scenario, load, seed). Policies are then
%   compared on identical traffic - a paired design, as recommended by the
%   validation guide.
%
%   Vectorised: exponential inter-arrival times binned into slots, which is
%   exact for a Poisson process and much faster than a per-slot loop.

if lambda <= 0
    arrivals = zeros(1, cfg.T);
    return
end

rs = RandStream('mt19937ar', 'Seed', seed * 104729 + 3);

nEst = ceil(lambda * cfg.T + 8 * sqrt(lambda * cfg.T) + 20);
tArr = cumsum(-log(rand(rs, 1, nEst)) / lambda);
tArr = tArr(tArr <= cfg.T);
arrivals = accumarray(ceil(tArr).', 1, [cfg.T 1]).';
end
