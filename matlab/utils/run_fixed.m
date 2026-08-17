function report = run_fixed(empty_folder, walk_folder, varargin)
% RUN_FIXED  Robust fixed radar gait analysis pipeline (auto-shape)
%            with AUTO-ZOOM: finds best 2-second window with 3-5 clean steps
%
% Usage:
%   report = run_fixed(empty_folder, walk_folder)
%   report = run_fixed(empty_folder, walk_folder, 'zoom_window_s', 2.0, ...)

    p = inputParser;
    addRequired(p, 'empty_folder', @ischar);
    addRequired(p, 'walk_folder',  @ischar);
    addParameter(p, 'frame_dt',                 0.078,        @isnumeric);
    addParameter(p, 'r_gate',                   [1.5, 7.0],   @isnumeric);
    addParameter(p, 'show',                     true,         @islogical);
    addParameter(p, 'bg_from_walk_s',           5.0,          @isnumeric);
    addParameter(p, 'nfft_r',                   1024,         @isnumeric);
    addParameter(p, 'nfft_d',                   256,          @isnumeric);
    addParameter(p, 'use_segments',             true,         @islogical);
    addParameter(p, 'segments_mode',            'hysteresis', @ischar);
    addParameter(p, 'segment_pad_s',            0.50,         @isnumeric);
    addParameter(p, 'min_gap_s',                0.5,          @isnumeric);
    addParameter(p, 'dynamic_gate_halfwidth_m', 0.0,          @isnumeric);
    addParameter(p, 'step_min_toe_mps',         0.20,         @isnumeric);
    addParameter(p, 'step_mode',                'hybrid',     @ischar);
    addParameter(p, 'save_separate_plots',      true,         @islogical);
    % Manual zoom: if set, used as-is. If empty, auto-zoom is computed.
    addParameter(p, 'zoom_time_range',          [],           @isnumeric);
    % Auto-zoom settings
    addParameter(p, 'zoom_window_s',            2.0,          @isnumeric);
    addParameter(p, 'zoom_min_steps',           3,            @isnumeric);
    addParameter(p, 'zoom_max_steps',           6,            @isnumeric);
    addParameter(p, 'zoom_regularity_thr',      0.35,         @isnumeric); % CV threshold
    addParameter(p, 'dpi_png',                  900,          @isnumeric);
    addParameter(p, 'vmin_prc',                 35.0,         @isnumeric);
    addParameter(p, 'vmax_prc',                 99.5,         @isnumeric);
    addParameter(p, 'min_range_db',             25.0,         @isnumeric);
    addParameter(p, 'gt_steps',                 [],           @isnumeric);

    parse(p, empty_folder, walk_folder, varargin{:});

    frame_dt               = p.Results.frame_dt;
    r_gate                 = p.Results.r_gate;
    show                   = p.Results.show;
    bg_from_walk_s         = p.Results.bg_from_walk_s;
    nfft_r                 = p.Results.nfft_r;
    nfft_d                 = p.Results.nfft_d;
    use_segments           = p.Results.use_segments;
    segments_mode          = p.Results.segments_mode;
    segment_pad_s          = p.Results.segment_pad_s;
    dynamic_gate_halfwidth_m = p.Results.dynamic_gate_halfwidth_m;
    step_min_toe_mps       = p.Results.step_min_toe_mps;
    step_mode              = p.Results.step_mode;
    save_separate_plots    = p.Results.save_separate_plots;
    zoom_time_range        = p.Results.zoom_time_range;
    zoom_window_s          = p.Results.zoom_window_s;
    zoom_min_steps         = p.Results.zoom_min_steps;
    zoom_max_steps         = p.Results.zoom_max_steps;
    zoom_regularity_thr    = p.Results.zoom_regularity_thr;
    dpi_png                = p.Results.dpi_png;
    vmin_prc               = p.Results.vmin_prc;
    vmax_prc               = p.Results.vmax_prc;
    min_range_db           = p.Results.min_range_db;

    fprintf('\n=== FIXED RADAR GAIT ANALYSIS ===\n');
    fprintf('Empty folder: %s\n', empty_folder);
    fprintf('Walk  folder: %s\n', walk_folder);
    fprintf('Frame dt: %.4f s  |  Range gate: [%.1f, %.1f] m\n\n', ...
            frame_dt, r_gate(1), r_gate(2));

    % ------------------------------------------------------------------ %
    % 1. Load data
    % ------------------------------------------------------------------ %
    fprintf('1. Loading WALK data...\n');
    [wk_adc, wk_cfg_json] = load_recording_auto(walk_folder);
    fprintf('   Walk adc (F,C,R,S): [%d %d %d %d]\n', size(wk_adc,1), size(wk_adc,2), size(wk_adc,3), size(wk_adc,4));

    cfg = derive_cfg_params(wk_cfg_json);

    fprintf('2. Loading EMPTY data...\n');
    [bg_adc, ~] = load_recording_auto(empty_folder);
    fprintf('   Empty adc (F,C,R,S): [%d %d %d %d]\n', size(bg_adc,1), size(bg_adc,2), size(bg_adc,3), size(bg_adc,4));

    sameShape = isequal(size(bg_adc,2), size(wk_adc,2)) && ...
                isequal(size(bg_adc,3), size(wk_adc,3)) && ...
                isequal(size(bg_adc,4), size(wk_adc,4));

    if ~sameShape
        warning(['EMPTY/WALK shape mismatch. Falling back to first %.1f s of WALK as background.'], bg_from_walk_s);
        n_bg   = max(1, min(size(wk_adc,1), round(bg_from_walk_s / frame_dt)));
        bg_mean = mean(wk_adc(1:n_bg,:,:,:), 1);
    else
        bg_mean = mean(bg_adc, 1);
    end

    % ------------------------------------------------------------------ %
    % 3. Background subtraction
    % ------------------------------------------------------------------ %
    fprintf('3. Background subtraction...\n');
    wk_adc = wk_adc - bg_mean;

    % ------------------------------------------------------------------ %
    % 4. RD / RT / VT maps
    % ------------------------------------------------------------------ %
    fprintf('4. Computing RD/RT/VT maps...\n');
    [rd, rt] = compute_rd_rt(wk_adc, cfg, nfft_r, nfft_d);

    r_axis = make_range_axis(cfg, nfft_r);
    v_axis = make_velocity_axis(cfg, nfft_d);
    r_idx  = range_gate_indices(r_axis, r_gate(1), r_gate(2));

    % ------------------------------------------------------------------ %
    % 5. Torso tracking
    % ------------------------------------------------------------------ %
    fprintf('5. Tracking torso...\n');
    torso_r = track_torso_range(rt, r_axis, r_idx);
    torso_v = torso_velocity(torso_r, frame_dt);

    % ------------------------------------------------------------------ %
    % 6. VT + toe envelope
    % ------------------------------------------------------------------ %
    fprintf('6. Computing VT map & toe envelope...\n');
    if dynamic_gate_halfwidth_m > 0
        vt      = vt_from_rd_dynamic(rd, r_axis, torso_r, dynamic_gate_halfwidth_m, 'sum');
        vt_mode = sprintf('dynamic(%.2fm)', dynamic_gate_halfwidth_m);
    else
        vt      = vt_from_rd_static(rd, r_idx, 'sum');
        vt_mode = 'static';
    end

    [toe, ~] = toe_envelope(vt, v_axis);

    % ------------------------------------------------------------------ %
    % 7. Walking segments
    % ------------------------------------------------------------------ %
    fprintf('7. Finding walking segments...\n');
    [walk_segments, thr_on, thr_off] = find_walking_segments(toe, frame_dt, ...
        'segments_mode', segments_mode, 'walk_k', 0.15, ...
        'min_walk_s', 1.0, 'min_gap_s', p.Results.min_gap_s);

    if use_segments && ~isempty(walk_segments)
        walking_mask = build_walking_mask(length(toe), walk_segments, frame_dt, segment_pad_s);
    else
        walking_mask = true(size(toe));
    end

    % ------------------------------------------------------------------ %
    % 8. Step detection
    % ------------------------------------------------------------------ %
    fprintf('8. Detecting steps...\n');
    [peaks_all, height_thr, prom_used] = detect_steps_from_toe(toe, frame_dt, ...
        'prom_k', 0.008, 'prom_floor', 0.004, 'height_prc', 4, ...
        'min_step_toe_mps', step_min_toe_mps, 'min_step_distance_s', 0.16);

    peaks_walk = peaks_all(walking_mask(peaks_all));

    if strcmp(step_mode, 'all')
        steps_for_stats    = peaks_all;
        steps_for_plot_all = peaks_all;
        steps_for_plot_used = peaks_all;
    elseif strcmp(step_mode, 'walking')
        steps_for_stats    = peaks_walk;
        steps_for_plot_all = [];
        steps_for_plot_used = steps_for_stats;
    else % hybrid
        steps_for_stats    = peaks_walk;
        steps_for_plot_all = peaks_all;
        steps_for_plot_used = steps_for_stats;
    end

    % ------------------------------------------------------------------ %
    % 9. AUTO-ZOOM: find best 2-second window with 3-5 clean steps
    % ------------------------------------------------------------------ %
    if isempty(zoom_time_range)
        fprintf('9. Auto-selecting zoom window (%.1f s, %d-%d steps)...\n', ...
                zoom_window_s, zoom_min_steps, zoom_max_steps);
        zoom_time_range = auto_select_zoom_window( ...
            steps_for_plot_used, toe, frame_dt, walk_segments, ...
            zoom_window_s, zoom_min_steps, zoom_max_steps, zoom_regularity_thr);

        if ~isempty(zoom_time_range)
            fprintf('   Auto-zoom selected: [%.2f, %.2f] s\n', zoom_time_range(1), zoom_time_range(2));
        else
            fprintf('   Auto-zoom: no suitable window found (will skip zoom plots).\n');
        end
    else
        fprintf('9. Using manual zoom_time_range: [%.2f, %.2f] s\n', zoom_time_range(1), zoom_time_range(2));
    end

    % ------------------------------------------------------------------ %
    % 10. Statistics
    % ------------------------------------------------------------------ %
    fprintf('10. Computing statistics...\n');
    total_steps_all     = length(peaks_all);
    total_steps_walking = length(peaks_walk);
    total_steps_used    = length(steps_for_stats);
    total_duration      = length(torso_r) * frame_dt;

    if use_segments && ~isempty(walk_segments) && ~strcmp(step_mode, 'all')
        walking_duration = sum(cellfun(@(s) (s(2) - s(1)) * frame_dt, walk_segments));
    else
        if length(steps_for_stats) >= 2
            walking_duration = (steps_for_stats(end) - steps_for_stats(1)) * frame_dt;
        else
            walking_duration = 0.0;
        end
    end

    cadence_spm = (total_steps_used / max(walking_duration, eps)) * 60.0;
    if isnan(cadence_spm) || isinf(cadence_spm), cadence_spm = 0.0; end

    if use_segments && ~isempty(walk_segments) && ~strcmp(step_mode, 'all')
        step_times   = step_intervals_within_segments(steps_for_stats, walk_segments, frame_dt);
        stride_times = stride_intervals_within_segments(steps_for_stats, walk_segments, frame_dt);
    else
        s = sort(steps_for_stats);
        step_times   = (length(s)>=2) * diff(s) * frame_dt;
        if length(s) >= 3
            stride_times = (s(3:end) - s(1:end-2)) * frame_dt;
        else
            stride_times = [];
        end
    end

    [mean_step_time,   step_time_cv]   = mean_and_cv(step_times);
    [mean_stride_time, stride_time_cv] = mean_and_cv(stride_times);

    if use_segments && ~isempty(walk_segments) && ~strcmp(step_mode, 'all')
        seg_for_stride = walk_segments;
    else
        seg_for_stride = {[1, length(torso_r)]};
    end
    s_len = stride_lengths_within_segments(torso_r, steps_for_stats, seg_for_stride);

    if ~isempty(s_len)
        avg_stride_length = mean(s_len);
        total_distance    = sum(s_len);
    else
        avg_stride_length = 0.0;
        total_distance    = 0.0;
    end

    if use_segments && ~isempty(walk_segments) && ~strcmp(step_mode, 'all')
        avg_walking_speed = median(abs(torso_v(walking_mask)));
    else
        avg_walking_speed = median(abs(torso_v));
    end

    % ------------------------------------------------------------------ %
    % 11. Build report struct
    % ------------------------------------------------------------------ %
    report = struct();
    report.step_mode                  = step_mode;
    report.total_steps_all            = total_steps_all;
    report.total_steps_walking        = total_steps_walking;
    report.total_steps_used_for_stats = total_steps_used;
    report.cadence_spm                = sprintf('%.2f', cadence_spm);
    report.mean_step_time_s           = sprintf('%.3f', mean_step_time);
    report.step_time_cv_pct           = sprintf('%.2f', step_time_cv);
    report.mean_stride_time_s         = sprintf('%.3f', mean_stride_time);
    report.stride_time_cv_pct        = sprintf('%.2f', stride_time_cv);
    report.avg_stride_length_m        = sprintf('%.3f', avg_stride_length);
    report.avg_walking_speed_mps      = sprintf('%.3f', avg_walking_speed);
    report.total_distance_m           = sprintf('%.3f', total_distance);
    report.total_duration_s           = sprintf('%.2f', total_duration);
    report.walking_duration_s         = sprintf('%.2f', walking_duration);
    report.num_walking_segments       = length(walk_segments);
    report.use_segments               = use_segments;
    report.segments_mode              = segments_mode;
    report.segment_pad_s              = sprintf('%.2f', segment_pad_s);
    report.vt_gate_mode               = vt_mode;
    report.walk_thr_on                = sprintf('%.3f', thr_on);
    report.walk_thr_off               = sprintf('%.3f', thr_off);
    report.step_min_toe_mps           = sprintf('%.2f', step_min_toe_mps);
    report.step_height_thr_used       = sprintf('%.3f', height_thr);
    report.step_prom_used             = sprintf('%.3f', prom_used);

    if ~isempty(zoom_time_range)
        report.auto_zoom_start_s = sprintf('%.2f', zoom_time_range(1));
        report.auto_zoom_end_s   = sprintf('%.2f', zoom_time_range(2));
    end

    if ~isempty(p.Results.gt_steps) && p.Results.gt_steps > 0
        err = total_steps_used - p.Results.gt_steps;
        report.gt_steps              = p.Results.gt_steps;
        report.step_count_error      = err;
        report.step_count_error_pct  = sprintf('%.2f', (100.0 * err / p.Results.gt_steps));
    end

    % ------------------------------------------------------------------ %
    % 12. Save outputs
    % ------------------------------------------------------------------ %
    fprintf('11. Saving results...\n');
    step_data = extract_per_step_data(steps_for_stats, toe, torso_r, torso_v, frame_dt);
    save_gait_data_to_csv(fullfile(walk_folder, 'Gait_Analysis_Results_FIXED.csv'), report, step_data);

    if save_separate_plots
        save_separate_plots_fixed(walk_folder, rt, vt, toe, r_axis, v_axis, ...
            frame_dt, walk_segments, steps_for_plot_all, steps_for_plot_used, step_min_toe_mps, ...
            report, zoom_time_range, vmin_prc, vmax_prc, min_range_db, dpi_png);
    end

    fprintf('\n=== ANALYSIS COMPLETE ===\n');
    fprintf('Total steps used: %d\n', total_steps_used);
    fprintf('Cadence: %s spm\n', report.cadence_spm);
    fprintf('Mean stride length: %s m\n', report.avg_stride_length_m);
    if ~isempty(zoom_time_range)
        fprintf('Auto-zoom window: [%.2f, %.2f] s\n', zoom_time_range(1), zoom_time_range(2));
    end

    if show
        fprintf('\nReport fields:\n');
        fn = fieldnames(report);
        for i = 1:length(fn)
            val = report.(fn{i});
            if islogical(val),   val_str = string(val);
            elseif isnumeric(val), val_str = num2str(val);
            else,                val_str = string(val);
            end
            fprintf('  %s: %s\n', fn{i}, val_str);
        end
    end
end


% =========================================================================
% AUTO-ZOOM HELPER
% Scans all walking-segment frames with a sliding window of zoom_window_s.
% Scores each candidate window by:
%   (a) step count in [zoom_min_steps, zoom_max_steps]
%   (b) step interval CV (lower = more regular)
%   (c) mean toe amplitude (higher = stronger signal)
% Returns the best [t_start, t_end] pair, or [] if none qualify.
% =========================================================================
function zoom_range = auto_select_zoom_window(steps_used, toe, frame_dt, ...
        walk_segments, window_s, min_steps, max_steps, regularity_thr)

    zoom_range = [];
    if isempty(steps_used) || length(steps_used) < min_steps
        return;
    end

    win_frames = round(window_s / frame_dt);
    n_frames   = length(toe);
    step_times_s = steps_used * frame_dt;   % step times in seconds

    % Build list of candidate start frames (only inside walking segments)
    if ~isempty(walk_segments)
        valid_starts = [];
        for k = 1:length(walk_segments)
            s0 = walk_segments{k}(1);
            s1 = walk_segments{k}(2);
            % window must fit fully inside segment
            seg_starts = s0 : round(0.1/frame_dt) : max(s0, s1 - win_frames);
            valid_starts = [valid_starts, seg_starts]; %#ok<AGROW>
        end
    else
        valid_starts = 1 : round(0.1/frame_dt) : max(1, n_frames - win_frames);
    end

    if isempty(valid_starts)
        return;
    end

    best_score = -Inf;
    best_range = [];

    for fi = valid_starts
        fe = fi + win_frames - 1;
        if fe > n_frames, continue; end

        t0 = (fi - 1) * frame_dt;
        t1 = (fe - 1) * frame_dt;

        % Steps inside this window
        mask  = (step_times_s >= t0) & (step_times_s <= t1);
        n_win = sum(mask);

        if n_win < min_steps || n_win > max_steps
            continue;
        end

        % Step interval regularity
        t_win = step_times_s(mask);
        if length(t_win) >= 2
            ivs = diff(t_win);
            cv  = std(ivs) / (mean(ivs) + eps);
        else
            cv = Inf;
        end

        if cv > regularity_thr
            continue;
        end

        % Mean toe amplitude in window (signal quality)
        toe_mean = mean(toe(fi:fe));

        % Score: reward more steps & strong signal, penalise irregularity
        score = n_win * toe_mean / (cv + 0.05);

        if score > best_score
            best_score = score;
            best_range = [t0, t1];
        end
    end

    zoom_range = best_range;
end


% =========================================================================
% IO: load recording folder (.mat or .npy), reorder to (F,C,R,S)
% =========================================================================
function [adc, cfg_json] = load_recording_auto(folder)
    folder = char(folder);

    matFile = fullfile(folder, 'radar_recording.mat');
    if exist(matFile, 'file')
        fprintf('   Loading from .mat...\n');
        S = load(matFile);
        if ~isfield(S, 'adc')
            error('MAT file has no variable "adc".');
        end
        adc = S.adc;
        cfgPath = fullfile(folder, 'config.json');
        if isfield(S, 'config')
            cfg_json = S.config;
        elseif exist(cfgPath, 'file')
            cfg_json = jsondecode(fileread(cfgPath));
        else
            cfg_json = struct();
        end
        adc = force_FCRS(adc, cfg_json);
        return;
    end

    npyFile = fullfile(folder, 'radar.npy');
    cfgPath = fullfile(folder, 'config.json');

    if ~exist(npyFile, 'file')
        error('Cannot find radar_recording.mat or radar.npy in:\n  %s', folder);
    end
    if ~exist(cfgPath, 'file')
        error('Cannot find config.json in:\n  %s', folder);
    end

    cfg_json = jsondecode(fileread(cfgPath));
    fprintf('   Loading from radar.npy...\n');
    adc_raw = readNPY(npyFile);
    adc = force_FCRS(adc_raw, cfg_json);
end


% =========================================================================
% Reorder to (Frames, Chirps, RX, Samples)
% =========================================================================
function x = force_FCRS(x, cfg_json)
    if ~isfloat(x), x = single(x); end
    if isreal(x) && ndims(x) >= 1 && size(x, ndims(x)) == 2
        x = complex(x(:,:,:,:,1), x(:,:,:,:,2));
    end

    expectedC = []; expectedS = []; expectedR = [];
    try
        s = cfg_json.device_config.fmcw_single_shape;
        expectedS = double(s.num_samples_per_chirp);
        expectedC = double(s.num_chirps_per_frame);
        expectedR = numel(s.rx_antennas);
    catch
        expectedR = 3;
    end

    shp = size(x);
    nd  = ndims(x);

    iR = find(shp == expectedR, 1, 'first');
    if isempty(iR)
        error('Cannot find RX=%d axis in shape [%s]', expectedR, num2str(shp));
    end

    if ~isempty(expectedC)
        iC = find(shp == expectedC, 1, 'first');
        if isempty(iC)
            error('Cannot find chirps=%d in shape [%s]', expectedC, num2str(shp));
        end
    else
        cand = setdiff(1:nd, iR);
        for gv = [64 128 32 16]
            ii = find(shp(cand) == gv, 1);
            if ~isempty(ii), iC = cand(ii); break; end
        end
    end

    if ~isempty(expectedS)
        iS = find(shp == expectedS, 1, 'first');
        if isempty(iS)
            error('Cannot find samples=%d in shape [%s]', expectedS, num2str(shp));
        end
    else
        cand = setdiff(1:nd, [iR iC]);
        [~, idx] = min(shp(cand));
        iS = cand(idx);
    end

    candF = setdiff(1:nd, [iC iR iS]);
    if numel(candF) ~= 1
        error('Cannot infer frame axis from shape [%s]', num2str(shp));
    end
    iF = candF(1);

    x = permute(x, [iF iC iR iS]);
    if ~isa(x, 'single'), x = single(x); end
end