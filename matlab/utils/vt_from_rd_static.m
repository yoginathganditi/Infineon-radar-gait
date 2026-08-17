function vt = vt_from_rd_static(rd, r_idx, mode)
    % VT_FROM_RD_STATIC Extract VT map using static range gate
    % Inputs:
    %   rd: (F, R, V) range-Doppler map
    %   r_idx: range gate indices
    %   mode: 'sum' or 'max'
    % Output:
    %   vt: (V, F) velocity-time map
    
    if nargin < 3, mode = 'sum'; end
    
    if strcmp(mode, 'sum')
        vt = sum(rd(:, r_idx, :), 2);  % Sum over range -> (F, 1, V)
    else
        vt = max(rd(:, r_idx, :), [], 2);  % Max over range -> (F, 1, V)
    end
    
    % Remove singleton dimension and transpose to (V, F)
    vt = squeeze(vt);
    if size(vt, 1) ~= size(rd, 3)
        vt = vt.';
    end
end