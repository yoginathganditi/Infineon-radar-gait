function [vmin, vmax] = robust_jet_limits(db2d, vmin_prc, vmax_prc, min_range_db)
    % ROBUST_JET_LIMITS Compute robust colormap limits
    % Inputs:
    %   db2d: 2D array in dB
    %   vmin_prc: minimum percentile (default 35.0)
    %   vmax_prc: maximum percentile (default 99.5)
    %   min_range_db: minimum range in dB (default 25.0)
    % Outputs:
    %   vmin, vmax: colormap limits
    
    if nargin < 2, vmin_prc = 35.0; end
    if nargin < 3, vmax_prc = 99.5; end
    if nargin < 4, min_range_db = 25.0; end
    
    lo = prctile(db2d(:), vmin_prc);
    hi = prctile(db2d(:), vmax_prc);
    
    if (hi - lo) < min_range_db
        hi = lo + min_range_db;
    end
    
    vmin = lo;
    vmax = hi;
end