function [walk_segments, thr_on, thr_off] = find_walking_segments(toe, frame_dt, varargin)
    % FIND_WALKING_SEGMENTS Find walking segments from toe envelope
    % Inputs:
    %   toe: (F,) toe envelope
    %   frame_dt: frame time interval (s)
    %   Optional:
    %     segments_mode: 'hysteresis', 'basic', or 'none'
    %     walk_k: threshold multiplier (default 0.15)
    %     min_walk_s: minimum walking segment duration (s, default 1.0)
    %     min_gap_s: minimum gap between segments (s, default 0.5)
    % Outputs:
    %   walk_segments: cell array of [start, end] frame pairs
    %   thr_on: threshold for turning on
    %   thr_off: threshold for turning off
    
    p = inputParser;
    addParameter(p, 'segments_mode', 'hysteresis', @ischar);
    addParameter(p, 'walk_k', 0.15, @isnumeric);
    addParameter(p, 'min_walk_s', 1.0, @isnumeric);
    addParameter(p, 'min_gap_s', 0.5, @isnumeric);
    parse(p, varargin{:});
    
    segments_mode = p.Results.segments_mode;
    walk_k = p.Results.walk_k;
    min_walk_s = p.Results.min_walk_s;
    min_gap_s = p.Results.min_gap_s;
    
    toe = toe(:)';  % Ensure row vector
    toe_s = imgaussfilt(toe, 1.0, 'FilterSize', 5);
    base = median(toe_s);
    spread = mad(toe_s);
    
    if strcmp(segments_mode, 'none')
        walk_segments = {};
        thr_on = [];
        thr_off = [];
        return;
    end
    
    if strcmp(segments_mode, 'basic')
        thr = base + walk_k * spread;
        walk = toe_s > thr;
        se = strel('disk', 1);
        % Apply dilation multiple times in a loop
        for i = 1:10
            walk = imdilate(walk, se);
        end
        % Apply erosion once
        walk = imerode(walk, se);
        walk_segments = segments_from_bool(walk, frame_dt, min_walk_s, min_gap_s);
        thr_on = thr;
        thr_off = thr;
        return;
    end
    
    % Hysteresis
    thr_on = base + walk_k * spread;
    thr_off = base + (walk_k * 0.92) * spread;
    
    walk = false(size(toe_s));
    state = false;
    for i = 1:length(toe_s)
        if ~state && (toe_s(i) >= thr_on)
            state = true;
        elseif state && (toe_s(i) <= thr_off)
            state = false;
        end
        walk(i) = state;
    end
    
    se = strel('disk', 1);
    % Apply dilation multiple times in a loop
    for i = 1:8
        walk = imdilate(walk, se);
    end
    % Apply erosion once
    walk = imerode(walk, se);
    
    walk_segments = segments_from_bool(walk, frame_dt, min_walk_s, min_gap_s);
end

function segments = segments_from_bool(walk_bool, frame_dt, min_walk_s, min_gap_s)
    walk = walk_bool(:)';
    segments = {};
    n = length(walk);
    i = 1;
    min_len = max(1, round(min_walk_s / frame_dt));
    min_gap = max(1, round(min_gap_s / frame_dt));
    
    while i <= n
        if ~walk(i)
            i = i + 1;
            continue;
        end
        a = i;
        while i <= n && walk(i)
            i = i + 1;
        end
        b = i;
        if (b - a) >= min_len
            segments{end+1} = [a, b];
        end
    end
    
    % Merge close segments
    if isempty(segments), return; end
    merged = {segments{1}};
    for i = 2:length(segments)
        if (segments{i}(1) - merged{end}(2)) < min_gap
            merged{end}(2) = segments{i}(2);
        else
            merged{end+1} = segments{i};
        end
    end
    segments = merged;
end