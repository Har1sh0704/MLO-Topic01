function t = tcrit95(df)
%TCRIT95  Two-sided 95% Student-t critical value, base MATLAB only.
%
%   tinv() lives in the Statistics toolbox. With 10 replications (df = 9)
%   the value is 2.262; the table below covers the small degrees of freedom
%   we actually use and falls back to the normal quantile for large df.

tbl_df  = [1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 ...
           21 22 23 24 25 26 27 28 29 30 40 60 120];
tbl_val = [12.706 4.303 3.182 2.776 2.571 2.447 2.365 2.306 2.262 2.228 ...
           2.201 2.179 2.160 2.145 2.131 2.120 2.110 2.101 2.093 2.086 ...
           2.080 2.074 2.069 2.064 2.060 2.056 2.052 2.048 2.045 2.042 ...
           2.021 2.000 1.980];

df = max(1, round(df));
if df >= 120
    t = 1.960;
else
    t = interp1(tbl_df, tbl_val, df, 'nearest');
end
end
