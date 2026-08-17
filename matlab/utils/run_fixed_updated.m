function report = run_fixed_updated(empty_folder, walk_folder, varargin)
% =========================================================================
%  RUN_FIXED_UPDATED  — Fixed corridor radar gait analysis
%
%  Handles BOTH recording formats:
%    OLD (RadarFusionGUI .mat): radar_recording.mat, var='adc', [F,C,R,S] complex
%    NEW (Raspberry Pi .mat):   radar.mat, var='radar_data', [F,R,C,S] single
%
%  New recording confirmed:
%    radar_data: [774 x 3 x 128 x 280]  single
%    F=774 frames, RX=3, Chirps=128, Samples=280
%    Config: 61-63 GHz, BW=2GHz, fs=1.006MHz, frame_dt=0.0773s
%    Range resolution = c/(2*B) = 0.075 m
%    Max unambiguous range ~ 10.49 m  (good for corridor)
%
%  Usage:
%    report = run_fixed_updated(empty_folder, walk_folder)
%    report = run_fixed_updated(empty_folder, walk_folder, 'r_gate',[1.5 7.0])
% =========================================================================

clc;

%% --- Input parser -------------------------------------------------------
p = inputParser;
addRequired(p, 'empty_folder', @(x) ischar(x)||isstring(x));
addRequired(p, 'walk_folder',  @(x) ischar(x)||isstring(x));

% Core settings
addParameter(p, 'r_gate',               [1.0, 8.0],   @isnumeric);  % corridor ROI (m)
addParameter(p, 'use_rx',               1,             @isnumeric);  % which RX to use (1-3)
addParameter(p, 'nfft_r',               512,           @isnumeric);
addParameter(p, 'nfft_d',               256,           @isnumeric);
addParameter(p, 'do_clutter_remove',    true,          @islogical);  % slow-time mean removal
addParameter(p, 'bg_from_walk_s',       5.0,           @isnumeric);  % fallback BG duration

% Step detection
addParameter(p, 'step_min_toe_mps',     0.20,          @isnumeric);
addParameter(p, 'step_mode',            'hybrid',      @ischar);     % hybrid/all/walking
addParameter(p, 'use_segments',         true,          @islogical);
addParameter(p, 'segments_mode',        'hysteresis',  @ischar);
addParameter(p, 'segment_pad_s',        0.30,          @isnumeric);
addParameter(p, 'min_gap_s',            0.5,           @isnumeric);

% Output
addParameter(p, 'show',                 true,          @islogical);
addParameter(p, 'save_plots',           true,          @islogical);
addParameter(p, 'dpi_png',              200,           @isnumeric);
addParameter(p, 'gt_steps',             [],            @isnumeric);
addParameter(p, 'zoom_time_range',      [],            @isnumeric);

parse(p, empty_folder, walk_folder, varargin{:});
opt = p.Results;

empty_folder = char(opt.empty_folder);
walk_folder  = char(opt.walk_folder);

fprintf('\n=== FIXED RADAR GAIT ANALYSIS (UPDATED) ===\n');
fprintf('Walk:  %s\n', walk_folder);
fprintf('Empty: %s\n\n', empty_folder);

%% -----------------------------------------------------------------------
%  STEP 1: Load config
%% -----------------------------------------------------------------------
cfg_path = fullfile(walk_folder, 'config.json');
if ~isfile(cfg_path)
    error('config.json not found in walk folder: %s', walk_folder);
end
cfg_json = jsondecode(fileread(cfg_path));
cfg      = parse_radar_config(cfg_json);

fprintf('Config loaded:\n');
fprintf('  Freq:     %.0f - %.0f GHz  (BW=%.1f GHz)\n', cfg.f_start/1e9, cfg.f_end/1e9, cfg.B/1e9);
fprintf('  fs:       %.3f MHz | Chirps: %d | Samples: %d | RX: %d\n', cfg.fs/1e6, cfg.n_chirps, cfg.n_samp, cfg.n_rx);
fprintf('  Frame dt: %.4f s (%.2f fps)\n', cfg.frame_dt, 1/cfg.frame_dt);
fprintf('  Range res: %.4f m | Max range: ~%.2f m\n\n', cfg.range_res, cfg.r_max);

%% -----------------------------------------------------------------------
%  STEP 2: Load walk data
%% -----------------------------------------------------------------------
fprintf('Loading WALK data...\n');
[wk_data, wk_fmt] = load_radar_mat(walk_folder, cfg);
% wk_data: [F x n_chirps x n_samp] complex single (one RX selected)
fprintf('  Walk: %d frames x %d chirps x %d samples | format: %s\n\n', ...
    size(wk_data,1), size(wk_data,2), size(wk_data,3), wk_fmt);

%% -----------------------------------------------------------------------
%  STEP 3: Load empty / background
%% -----------------------------------------------------------------------
fprintf('Loading EMPTY data...\n');
bg_data = load_background(empty_folder, walk_folder, wk_data, cfg, opt.bg_from_walk_s);
fprintf('  Background loaded.\n\n');

%% -----------------------------------------------------------------------
%  STEP 4: Background subtraction
%% -----------------------------------------------------------------------
fprintf('Subtracting background...\n');
wk_data = wk_data - bg_data;

%% -----------------------------------------------------------------------
%  STEP 5: Build range/velocity axes
%% -----------------------------------------------------------------------
n_pos   = floor(opt.nfft_r / 2) + 1;   % one-sided for real data
r_axis  = build_range_axis(cfg, opt.nfft_r);
v_axis  = build_velocity_axis(cfg, opt.nfft_d);

fprintf('Axes:\n');
fprintf('  Range:    0 -> %.3f m  (res=%.4f m)\n', max(r_axis), cfg.range_res);
fprintf('  Velocity: %.2f -> %.2f m/s\n\n', min(v_axis), max(v_axis));

% Range gate indices
r_idx = find(r_axis >= opt.r_gate(1) & r_axis <= opt.r_gate(2));
if isempty(r_idx)
    error('r_gate [%.1f %.1f] has no bins. Max range=%.2f m.', ...
        opt.r_gate(1), opt.r_gate(2), max(r_axis));
end
fprintf('Range gate: %.2f - %.2f m (%d bins)\n\n', ...
    r_axis(r_idx(1)), r_axis(r_idx(end)), numel(r_idx));

%% -----------------------------------------------------------------------
%  STEP 6: Compute RT and RD maps
%% -----------------------------------------------------------------------
fprintf('Computing RT and RD maps...\n');
F = size(wk_data, 1);

% Windows
w_r = reshape(hann(size(wk_data,3), 'periodic'), 1, 1, []);
w_d = reshape(hann(size(wk_data,2), 'periodic'), 1, [], 1);

% Pre-allocate
RT = zeros(F, opt.nfft_r, 'single');
VT = zeros(F, opt.nfft_d, 'single');

chunk = 200;
n_chunks = ceil(F / chunk);

for ch = 1:n_chunks
    f1 = (ch-1)*chunk + 1;
    f2 = min(ch*chunk, F);
    x  = wk_data(f1:f2, :, :);   % Fc x n_chirps x n_samp

    % Range FFT
    Xr = fft(x .* w_r, opt.nfft_r, 3);   % Fc x n_chirps x nfft_r

    % RT: mean over chirps
    RT(f1:f2, :) = 20*log10(squeeze(mean(abs(Xr), 2)) + 1e-12);

    % Clutter removal
    if opt.do_clutter_remove
        Xr = Xr - mean(Xr, 2);
    end

    % Doppler FFT -> VT summed over range gate
    Xd = fftshift(fft(Xr .* w_d, opt.nfft_d, 2), 2);   % Fc x nfft_d x nfft_r
    VT_chunk = squeeze(sum(abs(Xd(:, :, r_idx)), 3));    % Fc x nfft_d
    VT(f1:f2, :) = 20*log10(single(VT_chunk) + 1e-12);

    fprintf('  Chunk %d/%d\r', ch, n_chunks);
end
fprintf('\nRT/VT done.\n\n');

%% -----------------------------------------------------------------------
%  STEP 7: Time axis
%% -----------------------------------------------------------------------
t_axis = (0:F-1)' * cfg.frame_dt;
t_s    = t_axis;

%% -----------------------------------------------------------------------
%  STEP 8: Torso tracking from RT
%% -----------------------------------------------------------------------
fprintf('Tracking torso...\n');
torso_r = zeros(F, 1);
for f = 1:F
    [~, pk] = max(RT(f, r_idx));
    torso_r(f) = r_axis(r_idx(pk));
end
torso_r  = smooth1d(torso_r, 5);
torso_v  = [0; diff(torso_r)] / cfg.frame_dt;
torso_v  = smooth1d(torso_v, 5);

%% -----------------------------------------------------------------------
%  STEP 9: Foot velocity envelope from VT
%% -----------------------------------------------------------------------
fprintf('Extracting foot velocity envelope...\n');
toe = zeros(F, 1);
for f = 1:F
    row      = double(VT(f, :));
    med      = median(row);
    mad_val  = median(abs(row - med));
    mask     = row > (med + 2*mad_val);
    vabs     = abs(v_axis(mask));
    if any(mask)
        toe(f) = prctile(vabs, 98);
    else
        toe(f) = 0;
    end
end
toe = smooth1d(toe, 3);

%% -----------------------------------------------------------------------
%  STEP 10: Walking segment detection
%% -----------------------------------------------------------------------
fprintf('Detecting walking segments...\n');
[walk_segs, thr_on, thr_off] = detect_walk_segments(toe, cfg.frame_dt, ...
    opt.segments_mode, opt.min_gap_s);

if opt.use_segments && ~isempty(walk_segs)
    walk_mask = build_walk_mask(F, walk_segs, cfg.frame_dt, opt.segment_pad_s);
    fprintf('  Found %d walking segments.\n\n', numel(walk_segs));
else
    walk_mask = true(F, 1);
    fprintf('  No segments — using full recording.\n\n');
end

%% -----------------------------------------------------------------------
%  STEP 11: Step detection
%% -----------------------------------------------------------------------
fprintf('Detecting steps...\n');
[peaks_all, h_thr, prom_used] = detect_steps(toe, cfg.frame_dt, opt.step_min_toe_mps);
peaks_walk = peaks_all(walk_mask(peaks_all));

switch opt.step_mode
    case 'all';     steps = peaks_all;
    case 'walking'; steps = peaks_walk;
    otherwise;      steps = peaks_walk;   % hybrid default
end

fprintf('  All peaks: %d  |  Walking peaks: %d  |  Used: %d\n\n', ...
    numel(peaks_all), numel(peaks_walk), numel(steps));

%% -----------------------------------------------------------------------
%  STEP 12: Gait metrics
%% -----------------------------------------------------------------------
fprintf('Computing gait metrics...\n');
[metrics, step_dt] = compute_gait_metrics(steps, walk_segs, walk_mask, ...
    cfg.frame_dt, opt.use_segments, opt.step_mode, torso_r, torso_v, F);

%% -----------------------------------------------------------------------
%  STEP 13: MAPE vs ground truth
%% -----------------------------------------------------------------------
if ~isempty(opt.gt_steps) && opt.gt_steps > 0
    mape = 100 * abs(numel(steps) - opt.gt_steps) / opt.gt_steps;
    fprintf('  GT steps: %d  |  Detected: %d  |  MAPE: %.2f%%\n', ...
        opt.gt_steps, numel(steps), mape);
    metrics.gt_steps  = opt.gt_steps;
    metrics.mape_pct  = mape;
end

%% -----------------------------------------------------------------------
%  STEP 14: Save plots
%% -----------------------------------------------------------------------
if opt.save_plots
    fprintf('Saving plots...\n');
    save_all_plots(walk_folder, RT, VT, toe, r_axis, v_axis, t_s, ...
        r_idx, walk_segs, peaks_all, steps, opt.step_min_toe_mps, ...
        metrics, opt.zoom_time_range, opt.dpi_png);
end

%% -----------------------------------------------------------------------
%  STEP 15: Save CSV
%% -----------------------------------------------------------------------
save_csv(walk_folder, metrics, steps, toe, torso_r, torso_v, cfg.frame_dt);

%% -----------------------------------------------------------------------
%  STEP 16: Build report
%% -----------------------------------------------------------------------
report = build_report(metrics, numel(peaks_all), numel(peaks_walk), ...
    numel(steps), opt, thr_on, thr_off, h_thr, prom_used, wk_fmt);

if opt.show
    fprintf('\n=== REPORT ===\n');
    fn = fieldnames(report);
    for i = 1:numel(fn)
        v = report.(fn{i});
        if isnumeric(v); vs = num2str(v);
        elseif islogical(v); vs = mat2str(v);
        else; vs = char(v); end
        fprintf('  %-35s %s\n', fn{i}, vs);
    end
end

fprintf('\n=== DONE ===\n');
fprintf('Steps used: %d  |  Cadence: %.1f spm  |  Walk dur: %.1f s\n', ...
    numel(steps), metrics.cadence_spm, metrics.walk_dur_s);
end


%% =========================================================================
%%  LOADERS
%% =========================================================================

function [data3d, fmt] = load_radar_mat(folder, cfg)
% Returns [F x n_chirps x n_samp] complex single, one RX selected
    mat_path = fullfile(folder, 'radar.mat');
    if ~isfile(mat_path)
        mat_path = fullfile(folder, 'radar_recording.mat');
    end
    if ~isfile(mat_path)
        error('No radar.mat or radar_recording.mat found in: %s', folder);
    end

    info     = whos('-file', mat_path);
    var_name = pick_var(info);
    S        = load(mat_path, var_name);
    raw      = S.(var_name);
    fmt_str  = class(raw);

    % Determine layout from shape
    sz = size(raw);
    fprintf('  Raw shape: [%s]  class: %s\n', num2str(sz), fmt_str);

    % Convert to single complex
    if isinteger(raw) || (ischar(fmt_str) && contains(fmt_str,'int'))
        % uint16 real ADC (door-style) — convert
        raw  = single(raw) - 2048;
        fmt  = 'uint16_real_adc';
    else
        raw  = single(raw);
        fmt  = 'single_float';
    end

    % Reorder to [F, chirps, RX, samples] then pick RX 1
    data3d = reorder_to_FCRS(raw, sz, cfg);   % [F x C x RX x S]
    data3d = squeeze(data3d(:, :, 1, :));     % [F x C x S]  use RX 1

    % Make complex if real
    if isreal(data3d)
        % Apply Hilbert transform along fast-time to get analytic signal
        % Apply Hilbert per chirp along fast-time (sample dimension)
data3d_cplx = zeros(size(data3d), 'single');
for rx = 1:size(data3d, 3)
    for f = 1:size(data3d, 1)
        slice = squeeze(double(data3d(f, :, rx, :)));  % chirps x samples
        h = hilbert(slice.').' ;  % hilbert along columns (samples)
        data3d_cplx(f, :, rx, :) = single(h);
    end
end
data3d = data3d_cplx;
    end
end


function var_name = pick_var(info)
    candidates = {'radar_data','adc','data','frames','cube','raw_data','radar'};
    for k = 1:numel(candidates)
        if any(strcmp({info.name}, candidates{k}))
            var_name = candidates{k};
            return;
        end
    end
    var_name = info(1).name;
    fprintf('  WARNING: using first variable "%s"\n', var_name);
end


function data4d = reorder_to_FCRS(raw, sz, cfg)
% Reorder raw array to [Frames x Chirps x RX x Samples]
% Known layouts:
%   NEW Raspberry Pi: [F, RX, C, S]  -> permute [1,3,2,4]
%   OLD FusionGUI:    [F, C, RX, S]  -> already correct

    nd = ndims(raw);

    % Use config to identify axes
    nC = cfg.n_chirps;   % 128
    nS = cfg.n_samp;     % 280
    nR = cfg.n_rx;       % 3

    iC = find(sz == nC, 1);
    iS = find(sz == nS, 1);
    iR = find(sz == nR, 1);
    iF = setdiff(1:nd, [iC, iS, iR]);

    if numel(iF) ~= 1
        error('Cannot identify Frame axis in shape [%s]. Check config matches data.', num2str(sz));
    end

    data4d = permute(raw, [iF, iC, iR, iS]);
    fprintf('  Reordered: [F=%d, C=%d, RX=%d, S=%d]\n', ...
        size(data4d,1), size(data4d,2), size(data4d,3), size(data4d,4));
end


function bg = load_background(empty_folder, walk_folder, wk_data, cfg, bg_s)
    mat_path = fullfile(empty_folder, 'radar.mat');
    if ~isfile(mat_path)
        mat_path = fullfile(empty_folder, 'radar_recording.mat');
    end

    if isfile(mat_path)
        try
            [bg_data, ~] = load_radar_mat(empty_folder, cfg);
            % Check shape matches
            if isequal(size(bg_data,2:3), size(wk_data,2:3))
                bg = mean(bg_data, 1);
                fprintf('  Background from empty recording.\n');
                return;
            else
                fprintf('  Empty shape mismatch — falling back to walk BG.\n');
            end
        catch ME
            fprintf('  Empty load failed (%s) — falling back to walk BG.\n', ME.message);
        end
    else
        fprintf('  No empty recording found — using first %.1f s of walk.\n', bg_s);
    end

    % Fallback: use first bg_s seconds of walk
    n_bg = max(1, round(bg_s / cfg.frame_dt));
    n_bg = min(n_bg, size(wk_data, 1));
    bg   = mean(wk_data(1:n_bg, :, :), 1);
    fprintf('  Background from first %d frames (%.1f s) of walk.\n', n_bg, n_bg*cfg.frame_dt);
end


%% =========================================================================
%%  CONFIG PARSER
%% =========================================================================

function cfg = parse_radar_config(cfg_json)
    c = 299792458;
    s = cfg_json.device_config.fmcw_single_shape;

    cfg.f_start   = double(s.start_frequency_Hz);
    cfg.f_end     = double(s.end_frequency_Hz);
    cfg.fs        = double(s.sample_rate_Hz);
    cfg.n_chirps  = double(s.num_chirps_per_frame);
    cfg.n_samp    = double(s.num_samples_per_chirp);
    cfg.n_rx      = numel(s.rx_antennas);
    cfg.PRI       = double(s.chirp_repetition_time_s);
    cfg.frame_dt  = double(s.frame_repetition_time_s);

    cfg.B         = cfg.f_end - cfg.f_start;
    cfg.fc        = (cfg.f_start + cfg.f_end) / 2;
    cfg.lambda    = c / cfg.fc;
    cfg.Tc        = cfg.n_samp / cfg.fs;
    cfg.slope     = cfg.B / cfg.Tc;
    cfg.range_res = c / (2 * cfg.B);
    cfg.r_max     = c * cfg.fs / (4 * cfg.slope);
    cfg.v_max     = cfg.lambda / (4 * cfg.PRI);
end


%% =========================================================================
%%  AXES
%% =========================================================================

function r_axis = build_range_axis(cfg, nfft_r)
    c     = 299792458;
    f_b   = (0:nfft_r-1) * (cfg.fs / nfft_r);
    r_axis = (c * f_b) / (2 * cfg.slope);
end


function v_axis = build_velocity_axis(cfg, nfft_d)
    PRF    = 1 / cfg.PRI;
    fd     = ((-nfft_d/2):(nfft_d/2-1)) * (PRF / nfft_d);
    v_axis = (fd * cfg.lambda) / 2;
end


%% =========================================================================
%%  SIGNAL PROCESSING HELPERS
%% =========================================================================

function y = smooth1d(x, w)
    x = x(:);
    k = ones(w,1) / w;
    y = conv(x, k, 'same');
end


%% =========================================================================
%%  WALKING SEGMENT DETECTION
%% =========================================================================

function [segs, thr_on, thr_off] = detect_walk_segments(toe, frame_dt, mode, min_gap_s)
    segs    = {};
    thr_on  = 0;
    thr_off = 0;

    if strcmpi(mode, 'none')
        return;
    end

    % Hysteresis thresholds from toe envelope
    thr_on  = prctile(toe, 60) * 1.2;
    thr_off = prctile(toe, 40) * 0.8;

    in_walk  = false;
    seg_start = 1;
    min_gap_f = round(min_gap_s / frame_dt);
    last_off  = -inf;

    for f = 1:numel(toe)
        if ~in_walk && toe(f) >= thr_on
            % Merge with previous segment if gap is small
            if ~isempty(segs) && (f - last_off) < min_gap_f
                seg_start = segs{end}(1);
                segs(end) = [];
            else
                seg_start = f;
            end
            in_walk = true;
        elseif in_walk && toe(f) < thr_off
            segs{end+1} = [seg_start, f]; %#ok<AGROW>
            last_off = f;
            in_walk  = false;
        end
    end
    if in_walk
        segs{end+1} = [seg_start, numel(toe)];
    end

    % Remove very short segments (<1 s)
    min_len = round(1.0 / frame_dt);
    segs = segs(cellfun(@(s) (s(2)-s(1)) >= min_len, segs));
end


function mask = build_walk_mask(F, segs, frame_dt, pad_s)
    mask   = false(F, 1);
    pad_f  = round(pad_s / frame_dt);
    for k = 1:numel(segs)
        f1 = max(1, segs{k}(1) - pad_f);
        f2 = min(F, segs{k}(2) + pad_f);
        mask(f1:f2) = true;
    end
end


%% =========================================================================
%%  STEP DETECTION
%% =========================================================================

function [peaks, h_thr, prom_used] = detect_steps(toe, frame_dt, min_mps)
    min_dist_f = round(0.16 / frame_dt);   % min 160 ms between steps
    h_thr      = max(min_mps, prctile(toe(toe>0), 4));
    prom_used  = max(0.004, 0.008 * max(toe));

    [~, peaks] = findpeaks(toe, ...
        'MinPeakHeight',      h_thr, ...
        'MinPeakProminence',  prom_used, ...
        'MinPeakDistance',    min_dist_f);
    peaks = peaks(:)';
end


%% =========================================================================
%%  GAIT METRICS
%% =========================================================================

function [m, step_dt] = compute_gait_metrics(steps, segs, walk_mask, ...
        frame_dt, use_segs, step_mode, torso_r, torso_v, F)

    m = struct();
    step_dt = [];

    % Walking duration
    if use_segs && ~isempty(segs) && ~strcmp(step_mode,'all')
        walk_dur = sum(cellfun(@(s)(s(2)-s(1))*frame_dt, segs));
    elseif numel(steps) >= 2
        walk_dur = (steps(end) - steps(1)) * frame_dt;
    else
        walk_dur = F * frame_dt;
    end

    n_steps = numel(steps);
    cadence = 0;
    if walk_dur > 0 && n_steps > 0
        cadence = (n_steps / walk_dur) * 60;
    end

    % Step intervals
    if n_steps >= 2
        s_sorted = sort(steps);
        step_dt  = diff(s_sorted) * frame_dt;
        % Keep intervals within walking segments
        if use_segs && ~isempty(segs)
            keep = true(size(step_dt));
            for k = 1:numel(step_dt)
                mid_f = round((s_sorted(k) + s_sorted(k+1)) / 2);
                keep(k) = walk_mask(mid_f);
            end
            step_dt = step_dt(keep);
        end
    end

    [m.mean_step_s, m.step_cv_pct] = mean_cv(step_dt);

    % Stride intervals (every other step)
    if n_steps >= 3
        s_sorted   = sort(steps);
        stride_dt  = (s_sorted(3:end) - s_sorted(1:end-2)) * frame_dt;
    else
        stride_dt = [];
    end
    [m.mean_stride_s, m.stride_cv_pct] = mean_cv(stride_dt);

    % Speed & distance from torso
    if use_segs && ~isempty(segs)
        wm_idx = find(walk_mask);
        m.avg_speed_mps = median(abs(torso_v(wm_idx)));
    else
        m.avg_speed_mps = median(abs(torso_v));
    end

    m.n_steps      = n_steps;
    m.cadence_spm  = cadence;
    m.walk_dur_s   = walk_dur;
    m.total_dur_s  = F * frame_dt;
    m.n_segments   = numel(segs);
end


function [mn, cv] = mean_cv(x)
    if numel(x) >= 2
        mn = mean(x);
        cv = 100 * std(x) / mean(x);
    elseif numel(x) == 1
        mn = x; cv = 0;
    else
        mn = 0;  cv = 0;
    end
end


%% =========================================================================
%%  PLOTS
%% =========================================================================

function save_all_plots(folder, RT, VT, toe, r_axis, v_axis, t_s, ...
        r_idx, segs, peaks_all, steps_used, min_mps, metrics, zoom_t, dpi)

    t_min = t_s / 60;

    % --- RT map ---
    fig = figure('Visible','off','Position',[50 50 1600 500]);
    imagesc(t_s, r_axis(r_idx), double(RT(:,r_idx))'); axis xy;
    xlabel('Time (s)'); ylabel('Range (m)');
    title(sprintf('Range-Time (RT) | %d frames | %.1f s', size(RT,1), t_s(end)));
    colorbar; colormap('jet');
    auto_clim(gca, RT(:,r_idx));
    % Mark walking segments
    for k = 1:numel(segs)
        xline(t_s(segs{k}(1)),'w--','LineWidth',1);
        xline(t_s(segs{k}(2)),'w--','LineWidth',1);
    end
    exportgraphics(fig, fullfile(folder,'RT_fixed.png'),'Resolution',dpi);
    close(fig);

    % --- VT map ---
    fig = figure('Visible','off','Position',[50 50 1600 500]);
    imagesc(t_s, v_axis, double(VT)'); axis xy;
    xlabel('Time (s)'); ylabel('Velocity (m/s)');
    title('Velocity-Time (VT) | Clutter Removed | Fixed Corridor');
    colorbar; colormap('jet');
    auto_clim(gca, VT);
    yline(0,'w--','LineWidth',1);
    exportgraphics(fig, fullfile(folder,'VT_fixed.png'),'Resolution',dpi);
    close(fig);

    % --- Toe envelope + steps ---
    fig = figure('Visible','off','Position',[50 50 1600 400]);
    plot(t_s, toe, 'b', 'LineWidth', 1); hold on; grid on;
    yline(min_mps,'k--','LineWidth',1,'Label',sprintf('%.2f m/s threshold',min_mps));
    if ~isempty(peaks_all)
        plot(t_s(peaks_all), toe(peaks_all), 'ko', 'MarkerSize', 5);
    end
    if ~isempty(steps_used)
        plot(t_s(steps_used), toe(steps_used), 'r*', 'MarkerSize', 7);
    end
    % Shade walking segments
    yl = ylim;
    for k = 1:numel(segs)
        patch([t_s(segs{k}(1)) t_s(segs{k}(2)) t_s(segs{k}(2)) t_s(segs{k}(1))], ...
              [yl(1) yl(1) yl(2) yl(2)], 'g', 'FaceAlpha', 0.12, 'EdgeColor','none');
    end
    xlabel('Time (s)'); ylabel('Foot velocity (m/s)');
    title(sprintf('Foot Velocity Envelope | Steps: %d | Cadence: %.1f spm', ...
        metrics.n_steps, metrics.cadence_spm));
    legend({'Envelope','All peaks','Used steps','Walk segments'},'Location','northeast');
    exportgraphics(fig, fullfile(folder,'toe_envelope_fixed.png'),'Resolution',dpi);
    close(fig);

    % --- Zoomed VT (optional) ---
    if ~isempty(zoom_t) && numel(zoom_t) == 2
        tidx = t_s >= zoom_t(1) & t_s <= zoom_t(2);
        fig = figure('Visible','off','Position',[50 50 900 400]);
        imagesc(t_s(tidx), v_axis, double(VT(tidx,:))'); axis xy;
        xlabel('Time (s)'); ylabel('Velocity (m/s)');
        title(sprintf('VT Zoom [%.1f - %.1f s]', zoom_t(1), zoom_t(2)));
        colorbar; colormap('jet'); auto_clim(gca, VT(tidx,:));
        exportgraphics(fig, fullfile(folder,'VT_zoom_fixed.png'),'Resolution',dpi);
        close(fig);
    end

    fprintf('  Plots saved to: %s\n', folder);
end


function auto_clim(ax, data)
    flat = double(data(:));
    flat = flat(isfinite(flat));
    clim(ax, [prctile(flat,5), prctile(flat,95)]);
end


%% =========================================================================
%%  CSV + REPORT
%% =========================================================================

function save_csv(folder, metrics, steps, toe, torso_r, torso_v, frame_dt)
    t_steps = steps(:) * frame_dt;
    toe_v   = toe(steps(:));
    tr_v    = torso_r(min(steps(:), numel(torso_r)));
    tv_v    = torso_v(min(steps(:), numel(torso_v)));

    T = table(t_steps, toe_v(:), tr_v(:), tv_v(:), ...
        'VariableNames', {'step_time_s','foot_vel_mps','torso_range_m','torso_vel_mps'});
    writetable(T, fullfile(folder, 'gait_steps_fixed.csv'));

    % Summary CSV
    fn = fieldnames(metrics);
    vals = cellfun(@(f) num2str(metrics.(f)), fn, 'UniformOutput', false);
    T2 = table(fn, vals, 'VariableNames', {'Metric','Value'});
    writetable(T2, fullfile(folder, 'gait_summary_fixed.csv'));
    fprintf('  CSVs saved.\n');
end


function report = build_report(m, n_all, n_walk, n_used, opt, thr_on, thr_off, h_thr, prom, fmt)
    report.n_steps_all         = n_all;
    report.n_steps_walking     = n_walk;
    report.n_steps_used        = n_used;
    report.cadence_spm         = m.cadence_spm;
    report.mean_step_time_s    = m.mean_step_s;
    report.step_time_cv_pct    = m.step_cv_pct;
    report.mean_stride_time_s  = m.mean_stride_s;
    report.stride_time_cv_pct  = m.stride_cv_pct;
    report.avg_speed_mps       = m.avg_speed_mps;
    report.walk_duration_s     = m.walk_dur_s;
    report.total_duration_s    = m.total_dur_s;
    report.n_walk_segments     = m.n_segments;
    report.walk_thr_on         = thr_on;
    report.walk_thr_off        = thr_off;
    report.step_height_thr     = h_thr;
    report.step_prom_thr       = prom;
    report.step_mode           = opt.step_mode;
    report.use_segments        = opt.use_segments;
    report.r_gate_m            = opt.r_gate;
    report.data_format         = fmt;
    if isfield(m,'mape_pct')
        report.gt_steps  = m.gt_steps;
        report.mape_pct  = m.mape_pct;
    end
end