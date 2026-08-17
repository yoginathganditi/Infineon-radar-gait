function vt = vt_from_rd_dynamic(rd, r_axis, torso_r, halfwidth_m, mode)
    % VT_FROM_RD_DYNAMIC Extract VT map using dynamic range gate
    % Inputs:
    %   rd: (F, R, V) range-Doppler map
    %   r_axis: range axis values
    %   torso_r: (F,) torso range over time
    %   halfwidth_m: half-width of dynamic gate (m)
    %   mode: 'sum' or 'max'
    % Output:
    %   vt: (V, F) velocity-time map
    
    if nargin < 5, mode = 'sum'; end
    
    [F, R, V] = size(rd);
    vt_FV = zeros(F, V, 'single');
    
    for f = 1:F
        r0 = torso_r(f);
        idx = find((r_axis >= (r0 - halfwidth_m)) & (r_axis <= (r0 + halfwidth_m)));
        if ~isempty(idx)
            if strcmp(mode, 'sum')
                vt_FV(f, :) = sum(rd(f, idx, :), 2);
            else
                vt_FV(f, :) = max(rd(f, idx, :), [], 2);
            end
        end
    end
    
    % Transpose to (V, F)
    vt = vt_FV.';
end