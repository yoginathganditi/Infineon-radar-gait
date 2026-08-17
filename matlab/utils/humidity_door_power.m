function humidity_door_power()
% =========================================================================
%  HUMIDITY DOOR POWER EXTRACTOR — BGT60TR13C
%  For paper: "Indoor Humidity Estimation Using Differential mmWave
%              Backscatter Measurements"
%
%  EXPERIMENT SETUP (confirmed from photos + config):
%    - BGT60TR13C on tripod, 0.61 m from wooden door, 3ft (~0.91m) height
%    - Humidifier ran room from ~84% RH down to ~55% RH
%    - ThermoPro hygrometer on door frame for ground truth
%    - Config: 58-63.5 GHz | BW=5.5 GHz | fs=2MHz | 64 chirps | 64 samples
%    - Data: uint16 real ADC, centered at 2048
%
%  WHAT THIS CODE DOES (aligned with paper methodology):
%    1. Range FFT -> find door bin at ~0.61m
%    2. Extract door power vs time (in dB, arbitrary internal scale)
%    3. Smooth with sliding window to get clean humidity-correlated signal
%    4. NO clutter removal — door is static target, clutter removal kills it
%    5. Normalize power for plotting (matches Fig 5 in paper)
%    6. Save RT map, power vs time, and CSV for calibration curve fitting
%
%  OUTPUT: Use door_power_dB and t_min columns from CSV to plot against
%          your ThermoPro humidity log -> this gives your calibration curve
% =========================================================================

clc; close all;

%% ========== USER SETTINGS — EDIT HERE ==================================
folder = "C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Second_Session20260226-131652\RadarIfxAvian_00";

% Physical setup
radar_dist_m  = 0.61;    % measured distance from radar to door face (m)

% Range FFT settings
nfft_r        = 256;     % zero-padded FFT (more bins = smoother range profile)
r_gate        = [0.3 0.85]; % search gate around door (m) — DO NOT widen

% Power smoothing — CRITICAL for humidity sensing
% Humidity changes slowly (minutes), so we smooth aggressively
smooth_win_frames = 50;  % ~3.9 s window (50 * 0.0773 s) for noise reduction
                         % increase to 100 (~7.7s) for even smoother curve

% DO NOT enable clutter removal for static door target
% (clutter removal removes the door reflection itself)
do_clutter_remove = false;

chunk_size    = 500;
ADC_OFFSET    = 2048;

% Output files
outRT     = fullfile(folder, "RT_humidity.png");
outPower  = fullfile(folder, "door_power_humidity.png");
outNorm   = fullfile(folder, "door_power_normalized.png");
outRP     = fullfile(folder, "range_profile_mean.png");
outCSV    = fullfile(folder, "door_power_timeseries.csv");
outMat    = fullfile(folder, "humidity_results.mat");
%% =======================================================================

fprintf("=== Humidity Door Power Extractor ===\n");
fprintf("Folder: %s\n\n", folder);

mat_path = fullfile(folder, "radar.mat");
cfg_path = fullfile(folder, "config.json");
if ~isfile(mat_path); error("Missing: %s", mat_path); end
if ~isfile(cfg_path); error("Missing: %s", cfg_path); end

%% --- Load config --------------------------------------------------------
cfg      = jsondecode(fileread(cfg_path));
s        = cfg.device_config.fmcw_single_shape;
fs       = double(s.sample_rate_Hz);           % 2e6 Hz
f_start  = double(s.start_frequency_Hz);       % 58e9 Hz
f_end    = double(s.end_frequency_Hz);         % 63.5e9 Hz
frame_dt = double(s.frame_repetition_time_s);  % 0.0773 s
n_chirps = double(s.num_chirps_per_frame);     % 64
n_samp   = double(s.num_samples_per_chirp);    % 64

fprintf("Config:\n");
fprintf("  Freq:     %.0f - %.0f GHz  (BW = %.1f GHz)\n", ...
    f_start/1e9, f_end/1e9, (f_end-f_start)/1e9);
fprintf("  fs:       %.0f MHz | Chirps: %d | Samples: %d\n", ...
    fs/1e6, n_chirps, n_samp);
fprintf("  Frame dt: %.4f s (%.2f fps)\n\n", frame_dt, 1/frame_dt);

%% --- Build range axis (real ADC, one-sided FFT) -------------------------
c      = 299792458;
B      = f_end - f_start;       % 5.5 GHz
Tc     = n_samp / fs;           % 32 us
slope  = B / Tc;                % 171.875 THz/s

n_pos  = floor(nfft_r/2) + 1;
f_b    = (0:n_pos-1) * (fs / nfft_r);
r_axis = (c * f_b) / (2 * slope);

r_max  = c * fs / (4 * slope);
range_res = c / (2 * B);

fprintf("Range axis:\n");
fprintf("  Resolution: %.4f m | Max: %.3f m\n", range_res, r_max);
fprintf("  Door at %.2f m -> expected bin %d (%.4f m)\n\n", ...
    radar_dist_m, ...
    round(radar_dist_m / range_res), ...
    round(radar_dist_m / range_res) * range_res);

%% --- Inspect data -------------------------------------------------------
info    = whos('-file', mat_path);
vi      = info(strcmp({info.name}, 'radar_data'));
sz      = vi.size;
F_total = sz(1);

fprintf("radar_data: [%s]  %s  %.1f MB\n", num2str(sz), vi.class, vi.bytes/1e6);
fprintf("Total frames: %d | Duration: %.1f min (%.2f hr)\n\n", ...
    F_total, F_total*frame_dt/60, F_total*frame_dt/3600);

%% --- Pre-allocate -------------------------------------------------------
RT_all    = zeros(F_total, n_pos, 'single');
power_raw = zeros(F_total, 1, 'single');
mean_prof = zeros(1, n_pos, 'double');

%% --- Load data ----------------------------------------------------------
fprintf("Loading radar.mat...\n"); tic;
S   = load(mat_path, 'radar_data');
raw = S.radar_data;
clear S;
fprintf("Loaded in %.1f s\n\n", toc);

%% --- Hann window --------------------------------------------------------
w_r = reshape(hann(n_samp, 'periodic'), 1, 1, []);  % 1 x 1 x n_samp

n_chunks = ceil(F_total / chunk_size);

%% -----------------------------------------------------------------------
%  PASS 1: Range FFT -> RT + mean range profile
%  NO clutter removal — door is static, we want its reflection
%% -----------------------------------------------------------------------
fprintf("Computing RT (no clutter removal — static door target)...\n");

for ch = 1:n_chunks
    f1 = (ch-1)*chunk_size + 1;
    f2 = min(ch*chunk_size, F_total);

    % [Fc x n_chirps x n_samp] — squeeze out RX dim
    chunk = squeeze(raw(f1:f2, 1, :, :));

    % uint16 -> real centered float
    x = single(chunk) - ADC_OFFSET;

    % Hann window
    x = x .* w_r;

    % Real FFT, keep one-sided
    Xr_full = fft(x, nfft_r, 3);
    Xr      = Xr_full(:, :, 1:n_pos);      % Fc x n_chirps x n_pos

    % Power: coherent sum over chirps (better SNR than mean for static target)
    % Use mean of magnitude^2 -> power, then sqrt for amplitude
    RP = squeeze(mean(abs(Xr).^2, 2));     % Fc x n_pos  (power domain)
    RP = sqrt(RP);                          % back to amplitude domain
    RT_chunk = 20*log10(RP + 1e-12);

    RT_all(f1:f2, :) = RT_chunk;
    mean_prof = mean_prof + double(sum(RT_chunk, 1));

    fprintf("  Chunk %3d/%3d | Frames %6d-%6d\r", ch, n_chunks, f1, f2);
end
fprintf("\nRT done.\n\n");
mean_prof = mean_prof / F_total;

%% --- Identify door bin --------------------------------------------------
r_idx = find(r_axis >= r_gate(1) & r_axis <= r_gate(2));
if isempty(r_idx)
    error("r_gate [%.2f %.2f] m has no bins in range axis.", r_gate(1), r_gate(2));
end

[~, lp]  = max(mean_prof(r_idx));
pk_bin   = r_idx(lp);
pk_range = r_axis(pk_bin);

fprintf(">>> Door bin detected: %.4f m (expected: %.2f m) <<<\n", ...
    pk_range, radar_dist_m);
fprintf("    Range error: %.4f m (%.1f bins)\n\n", ...
    abs(pk_range - radar_dist_m), abs(pk_range - radar_dist_m)/range_res);

% Door power: average over a ±2 bin window around peak (robust to small shifts)
halfw   = 2;
door_bins = max(1, pk_bin-halfw) : min(n_pos, pk_bin+halfw);
fprintf("Using bins %d-%d (%.3f-%.3f m) for door power\n\n", ...
    door_bins(1), door_bins(end), r_axis(door_bins(1)), r_axis(door_bins(end)));

% Extract door power per frame (peak bin in window)
for f = 1:F_total
    [~, best] = max(RT_all(f, door_bins));
    power_raw(f) = RT_all(f, door_bins(best));
end

%% --- Smooth power -------------------------------------------------------
% Humidity changes on the scale of minutes — smooth aggressively
% This gives a clean monotonic curve that tracks RH
power_smooth = movmedian(double(power_raw), smooth_win_frames);

fprintf("Power stats (raw):    mean=%.2f dB, std=%.2f dB, range=[%.2f, %.2f]\n", ...
    mean(power_raw), std(power_raw), min(power_raw), max(power_raw));
fprintf("Power stats (smooth): mean=%.2f dB, std=%.2f dB, range=[%.2f, %.2f]\n\n", ...
    mean(power_smooth), std(power_smooth), min(power_smooth), max(power_smooth));

%% --- Normalize power (0 to 1, for paper Fig 5 style plots) -------------
p_min  = min(power_smooth);
p_max  = max(power_smooth);
if p_max > p_min
    power_norm = (power_smooth - p_min) / (p_max - p_min);
else
    power_norm = ones(size(power_smooth));
    warning("Power range is zero — normalization skipped.");
end

%% --- Time axes ----------------------------------------------------------
t_axis = (0:F_total-1)' * frame_dt;
t_min  = t_axis / 60;

fprintf("Recording duration: %.1f min (%.2f hr)\n\n", t_min(end), t_min(end)/60);

%% -----------------------------------------------------------------------
%  PLOTS
%% -----------------------------------------------------------------------
fprintf("Saving plots...\n");

r_disp = find(r_axis >= 0 & r_axis <= r_gate(2));

% ---- RT map (shows door as stable band at 0.61m) ----------------------
fig = figure("Visible","off","Position",[50 50 1800 550]);
imagesc(t_min, r_axis(r_disp), double(RT_all(:, r_disp))'); axis xy;
xlabel("Time (min)"); ylabel("Range (m)");
title(sprintf("Range-Time (RT) | Door @ %.3f m | %d frames | %.1f min | NO clutter removal", ...
    pk_range, F_total, t_min(end)));
colorbar; colormap("jet");
yline(pk_range,'w--','LineWidth',2,'Label',sprintf('Door %.3f m',pk_range));
yline(radar_dist_m,'g--','LineWidth',1.5,'Label',sprintf('Placed %.2f m',radar_dist_m));
pclim(gca, RT_all(:, r_disp));
exportgraphics(fig, outRT, "Resolution",200); close(fig);
fprintf("  RT:           %s\n", outRT);

% ---- Door power vs time (raw + smoothed) ------------------------------
fig = figure("Visible","off","Position",[50 50 1800 500]);
plot(t_min, power_raw,    'Color',[0.7 0.7 1], 'LineWidth',0.4); hold on; grid on;
plot(t_min, power_smooth, 'b', 'LineWidth',1.5);
xlabel("Time (min)"); ylabel("Door Power (dB, internal scale)");
title(sprintf("Door Backscatter Power | %.3f m | Humidity decreasing over session", pk_range));
legend({'Raw (per-frame)','Smoothed (movmedian)'},'Location','best');
xlim([0 t_min(end)]);

% Add annotation about expected trend
text(0.02, 0.05, 'Expected: power decreases as RH decreases (wood loses moisture)', ...
    'Units','normalized','FontSize',9,'Color','red');
exportgraphics(fig, outPower, "Resolution",200); close(fig);
fprintf("  Power:        %s\n", outPower);

% ---- Normalized power (paper Fig 5 style) -----------------------------
fig = figure("Visible","off","Position",[50 50 1200 500]);
plot(t_min, power_norm, 'b', 'LineWidth',1.5); grid on; hold on;
xlabel("Time (min)"); ylabel("Normalized Relative Power");
title(sprintf("Normalized Door Backscatter | %.3f m | (matches paper Fig 5 style)", pk_range));
ylim([-0.05 1.05]);
xlim([0 t_min(end)]);
text(0.02, 0.95, sprintf('Range: %.2f dB  to  %.2f dB', p_min, p_max), ...
    'Units','normalized','FontSize',9);
exportgraphics(fig, outNorm, "Resolution",200); close(fig);
fprintf("  Normalized:   %s\n", outNorm);

% ---- Mean range profile -----------------------------------------------
fig = figure("Visible","off","Position",[800 400 1000 500]);
plot(r_axis, mean_prof, 'b', 'LineWidth',1.5); grid on; hold on;
xline(pk_range,     'r--','LineWidth',2,'Label',sprintf('Detected %.3f m',pk_range));
xline(radar_dist_m, 'g--','LineWidth',2,'Label',sprintf('Placed %.2f m',radar_dist_m));
xlabel("Range (m)"); ylabel("Mean Power (dB)");
title(sprintf("Mean Range Profile | All %d frames | Door at %.3f m", F_total, pk_range));
xlim([0 r_gate(2)+0.1]);
legend({'Mean profile','Detected peak','Physical placement'},'Location','northeast');
exportgraphics(fig, outRP, "Resolution",200); close(fig);
fprintf("  Range profile: %s\n", outRP);

% ---- Save CSV ---------------------------------------------------------
% This is the main output for calibration curve fitting
% Match t_min against your ThermoPro humidity log to get power vs RH
T = table(...
    t_axis, ...
    t_min, ...
    double(power_raw), ...
    power_smooth, ...
    power_norm, ...
    'VariableNames', {'t_s','t_min','door_power_dB_raw','door_power_dB_smooth','door_power_normalized'});
writetable(T, outCSV);
fprintf("  CSV:           %s\n", outCSV);
fprintf("  (Use t_min + ThermoPro log to map power -> RH)\n");

% ---- Save .mat --------------------------------------------------------
r_ax_gate = r_axis(r_idx); %#ok<NASGU>
save(outMat, ...
    'RT_all','t_axis','t_min','r_axis','r_ax_gate', ...
    'pk_range','pk_bin','mean_prof', ...
    'power_raw','power_smooth','power_norm', ...
    'p_min','p_max','smooth_win_frames', '-v7.3');
fprintf("  MAT:           %s\n\n", outMat);

%% -----------------------------------------------------------------------
%  SUMMARY
%% -----------------------------------------------------------------------
fprintf("=== SUMMARY ===\n");
fprintf("Door detected at:   %.4f m  (placed at %.2f m, error=%.4f m)\n", ...
    pk_range, radar_dist_m, abs(pk_range-radar_dist_m));
fprintf("Power range:        %.2f to %.2f dB  (span=%.2f dB)\n", ...
    p_min, p_max, p_max-p_min);
fprintf("Duration:           %.1f min\n", t_min(end));
fprintf("Frames:             %d\n", F_total);
fprintf("\nNEXT STEP:\n");
fprintf("  1. Open door_power_timeseries.csv\n");
fprintf("  2. Open your ThermoPro humidity log (or manually noted RH vs clock time)\n");
fprintf("  3. Align t_min column with your RH readings\n");
fprintf("  4. Plot door_power_dB_smooth vs RH -> this is your calibration curve\n");
fprintf("  5. Fit linear model: Power = a0 - a1*RH  (paper Eq. 7)\n\n");
fprintf("=== DONE ===\n");
end


%% =========================================================================
%  Auto color limits: 5th-95th percentile
%% =========================================================================
function pclim(ax, data)
    flat = double(data(:));
    flat = flat(isfinite(flat));
    clim(ax, [prctile(flat,5), prctile(flat,95)]);
end