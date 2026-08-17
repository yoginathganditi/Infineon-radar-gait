function mask = build_walking_mask(n_frames, segments, frame_dt, pad_s)
    % BUILD_WALKING_MASK Build binary mask for walking segments
    % Inputs:
    %   n_frames: total number of frames
    %   segments: cell array of [start, end] frame pairs
    %   frame_dt: frame time interval (s)
    %   pad_s: padding time (s, default 0.0)
    % Output:
    %   mask: (n_frames,) binary mask
    
    if nargin < 4, pad_s = 0.0; end
    
    mask = false(1, n_frames);
    pad = max(0, round(pad_s / frame_dt));
    
    for i = 1:length(segments)
        s = segments{i};
        a2 = max(1, s(1) - pad);
        b2 = min(n_frames, s(2) + pad);
        mask(a2:b2) = true;
    end
end