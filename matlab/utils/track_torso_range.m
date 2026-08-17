function torso_r = track_torso_range(rt, r_axis, r_idx)
    % TRACK_TORSO_RANGE Track torso range over time
    % Inputs:
    %   rt: (F, R) range-time map
    %   r_axis: range axis values
    %   r_idx: range gate indices
    % Output:
    %   torso_r: (F,) torso range over time
    
    rt_g = rt(:, r_idx);
    [~, peak] = max(rt_g, [], 2);
    torso_r = r_axis(r_idx(peak));
    torso_r = imgaussfilt(torso_r, 1.0, 'FilterSize', 5);
end