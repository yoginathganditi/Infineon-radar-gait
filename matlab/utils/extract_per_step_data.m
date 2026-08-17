function step_data = extract_per_step_data(step_frames, toe, torso_r, torso_v, frame_dt)
    % EXTRACT_PER_STEP_DATA Extract per-step data
    % Inputs:
    %   step_frames: array of step frame indices
    %   toe: toe envelope
    %   torso_r: torso range
    %   torso_v: torso velocity
    %   frame_dt: frame time interval
    % Output:
    %   step_data: cell array of step data structures
    
    step_frames = sort(step_frames(:));
    step_data = {};
    
    for idx = 1:length(step_frames)
        frame = step_frames(idx);
        step_id = idx;
        time_s = (frame - 1) * frame_dt;  % 0-indexed time
        toe_velocity = toe(frame);
        torso_velocity_val = torso_v(frame);
        
        if idx == 1
            step_time_s = 0.0;
            step_length_cm = 0.0;
        else
            step_time_s = (frame - step_frames(idx-1)) * frame_dt;
            step_length_m = abs(torso_r(frame) - torso_r(step_frames(idx-1)));
            step_length_cm = step_length_m * 100.0;
        end
        
        if idx + 2 <= length(step_frames)
            stride_time_s = (step_frames(idx+2) - frame) * frame_dt;
            stride_length_cm = abs(torso_r(step_frames(idx+2)) - torso_r(frame)) * 100.0;
        else
            stride_time_s = 0.0;
            stride_length_cm = 0.0;
        end
        
        step_data{idx} = struct(...
            'step_id', step_id, ...
            'time_s', time_s, ...
            'toe_velocity_m_s', toe_velocity, ...
            'torso_velocity_m_s', torso_velocity_val, ...
            'step_time_s', step_time_s, ...
            'step_length_cm', step_length_cm, ...
            'stride_time_s', stride_time_s, ...
            'stride_length_cm', stride_length_cm);
    end
end