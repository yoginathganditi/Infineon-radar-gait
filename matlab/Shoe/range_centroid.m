function rc = range_centroid(rt, r_axis, r_idx)
    % RANGE_CENTROID Compute range centroid over time
    % Inputs:
    %   rt: (F, R) range-time map
    %   r_axis: range axis values
    %   r_idx: range gate indices
    % Output:
    %   rc: (F,) range centroid over time
    
    rt_g = rt(:, r_idx);
    r = r_axis(r_idx);
    denom = sum(rt_g, 2) + 1e-12;
    num = sum(rt_g .* r, 2);
    rc = num ./ denom;
    rc = imgaussfilt(rc, 1.5, 'FilterSize', 5);
end