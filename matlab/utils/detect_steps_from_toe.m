function [peaks, height_thr, prom_used] = detect_steps_from_toe(toe, frame_dt, varargin)
    % DETECT_STEPS_FROM_TOE Detect steps from toe envelope
    % Inputs:
    %   toe: (F,) toe envelope
    %   frame_dt: frame time interval (s)
    %   Optional parameters...
    % Outputs:
    %   peaks: array of peak frame indices (1-indexed)
    %   height_thr: height threshold used
    %   prom_used: prominence used
    
    p = inputParser;
    addParameter(p, 'prom_k', 0.008, @isnumeric);
    addParameter(p, 'prom_floor', 0.004, @isnumeric);
    addParameter(p, 'height_prc', 4, @isnumeric);
    addParameter(p, 'min_step_toe_mps', 0.20, @isnumeric);
    addParameter(p, 'min_step_distance_s', 0.16, @isnumeric);
    parse(p, varargin{:});
    
    prom_k = p.Results.prom_k;
    prom_floor = p.Results.prom_floor;
    height_prc = p.Results.height_prc;
    min_step_toe_mps = p.Results.min_step_toe_mps;
    min_step_distance_s = p.Results.min_step_distance_s;
    
    toe = toe(:);  % Ensure column vector for findpeaks
    min_dist = max(1, round(min_step_distance_s / frame_dt));
    
    % Prominence
    m = mad(toe);
    prom = max(prom_k * m, prom_floor);
    
    % Height threshold
    height_thr = prctile(toe, height_prc);
    height_thr = max(height_thr, min_step_toe_mps);
    
    % Find peaks
    % findpeaks returns: [peak_values, peak_locations]
    % We want the locations (indices), which is the second output
    [~, peak_locations] = findpeaks(toe, 'MinPeakHeight', height_thr, ...
        'MinPeakProminence', prom, 'MinPeakDistance', min_dist);
    
    % peak_locations are the frame indices (1-indexed)
    peaks = round(peak_locations(:));  % Ensure column vector and round
    peaks = peaks(peaks >= 1 & peaks <= length(toe));
    
    prom_used = prom;
end