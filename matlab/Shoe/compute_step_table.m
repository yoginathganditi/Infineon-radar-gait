function rows = compute_step_table(peaks, rc_m, v_axis, vt, frame_dt)
    % COMPUTE_STEP_TABLE Compute per-step data table for shoe-mounted
    % Inputs:
    %   peaks: array of peak frame indices
    %   rc_m: (F,) range centroid in meters
    %   v_axis: velocity axis values
    %   vt: (V, F) velocity-time map
    %   frame_dt: frame time interval
    % Output:
    %   rows: cell array of step data rows
    
    peaks = sort(peaks(:));
    rows = {};
    
    vpos = find(v_axis > 0);
    vneg = find(v_axis < 0);
    
    for i = 1:length(peaks)
        p = peaks(i);
        t = (p - 1) * frame_dt;
        
        if i == 1
            step_t = 0.0;
        else
            step_t = (p - peaks(i-1)) * frame_dt;
        end
        
        col = vt(:, p);
        
        % Approach velocity (negative velocities)
        if ~isempty(vneg)
            [~, idx] = max(col(vneg));
            v_app = abs(v_axis(vneg(idx)));
        else
            v_app = 0.0;
        end
        
        % Separation velocity (positive velocities)
        if ~isempty(vpos)
            [~, idx] = max(col(vpos));
            v_sep = abs(v_axis(vpos(idx)));
        else
            v_sep = 0.0;
        end
        
        % Distance alignment
        d_align_cm = rc_m(p) * 100.0;
        
        rows{i} = struct(...
            'step_id', i, ...
            'time_s', t, ...
            'step_time_s', step_t, ...
            'v_app', v_app, ...
            'v_sep', v_sep, ...
            'd_align_cm', d_align_cm);
    end
end