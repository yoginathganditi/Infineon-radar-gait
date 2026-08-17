function fog_count = fog_count_within_segments(peaks, segments, frame_dt, max_step_gap_s)
    % FOG_COUNT_WITHIN_SEGMENTS Count FOG (Freezing of Gait) episodes
    % Inputs:
    %   peaks: array of peak frame indices
    %   segments: cell array of walking segments
    %   frame_dt: frame time interval
    %   max_step_gap_s: maximum normal step gap (default 1.5s)
    % Output:
    %   fog_count: number of FOG episodes (step gaps > max_step_gap_s)
    
    if nargin < 4, max_step_gap_s = 1.5; end
    
    dt = step_intervals_within_segments(peaks, segments, frame_dt);
    if isempty(dt)
        fog_count = 0;
        return;
    end
    
    fog_count = sum(dt > max_step_gap_s);
end