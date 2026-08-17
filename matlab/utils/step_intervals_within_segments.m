function step_times = step_intervals_within_segments(peaks, segments, frame_dt)
    % STEP_INTERVALS_WITHIN_SEGMENTS Compute step intervals within walking segments
    % Inputs:
    %   peaks: array of peak frame indices
    %   segments: cell array of [start, end] frame pairs
    %   frame_dt: frame time interval (s)
    % Output:
    %   step_times: array of step intervals (s)
    
    seg_peaks = split_peaks_by_segments(peaks, segments);
    dts = [];
    
    for i = 1:length(seg_peaks)
        p = sort(seg_peaks{i});
        if length(p) >= 2
            % Ensure both are row vectors for horizontal concatenation
            intervals = diff(p) * frame_dt;
            intervals = intervals(:)';  % Make row vector
            dts = [dts, intervals];
        end
    end
    
    step_times = dts(:);  % Return as column vector
end

function seg_peaks = split_peaks_by_segments(peaks, segments)
    peaks = sort(peaks(:));  % Ensure column vector and sort
    seg_peaks = {};
    
    for i = 1:length(segments)
        s = segments{i};
        p = peaks((peaks >= s(1)) & (peaks < s(2)));
        if ~isempty(p)
            seg_peaks{end+1} = p;
        end
    end
end