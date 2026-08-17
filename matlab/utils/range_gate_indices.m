function r_idx = range_gate_indices(r_axis, rmin, rmax)
    % RANGE_GATE_INDICES Find indices for range gate
    % Inputs:
    %   r_axis: range axis values
    %   rmin: minimum range (m)
    %   rmax: maximum range (m)
    % Output:
    %   r_idx: indices where r_axis is between rmin and rmax
    
    r_idx = find((r_axis >= rmin) & (r_axis <= rmax));
end