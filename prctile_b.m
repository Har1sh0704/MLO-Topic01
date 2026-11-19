function v = prctile_b(x, p)
%PRCTILE_B  Percentile with linear interpolation (type 7), base MATLAB only.
%
%   The Statistics and Machine Learning Toolbox may not be installed, so
%   prctile() cannot be assumed. This is the same estimator numpy.percentile
%   uses by default, which keeps the numbers reproducible outside MATLAB.

x = sort(x(:));
n = numel(x);
if n == 0
    v = NaN;
    return
end
if n == 1
    v = x(1);
    return
end
r  = (n - 1) * p / 100 + 1;     % 1-based fractional rank
lo = floor(r);
hi = min(lo + 1, n);
w  = r - lo;
v  = x(lo) * (1 - w) + x(hi) * w;
end
