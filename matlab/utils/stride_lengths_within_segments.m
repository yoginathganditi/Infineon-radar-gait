function s_len = stride_lengths_within_segments(torso_r, peaks, segments)
    % STRIDE_LENGTHS_WITHIN_SEGMENTS Compute stride lengths within walking segments
    % Inputs:
    %   torso_r: (F,) torso range over time
    %   peaks: array of peak frame indices
    %   segments: cell array of [start, end] frame pairs
    % Output:
    %   s_len: array of stride lengths (m)
    
    if length(peaks) < 3 || isempty(segments)
        s_len = [];
        return;
    end
    
    all_sl = [];
    seg_peaks = split_peaks_by_segments(peaks, segments);
    
    for i = 1:length(seg_peaks)
        p = seg_peaks{i};
        if length(p) >= 3
            sl = abs(torso_r(p(3:end)) - torso_r(p(1:end-2)));
            sl = sl(:)';  % Make row vector
            all_sl = [all_sl, sl];
        end
    end
    
    s_len = all_sl(:);  % Return as column vector
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