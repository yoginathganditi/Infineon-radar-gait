function door_rt_vt_enhanced()
% =========================================================================
%  RT & VT PROCESSOR — BGT60TR13C Hand Motion (Raspberry Pi Recording)
%
%  DATA FORMAT CONFIRMED:
%    radar_data: [774 x 3 x 128 x 280]  single
%    Dim 1 = Frames  (774)
%    Dim 2 = RX antennas (3)
%    Dim 3 = Chirps per frame (128)
%    Dim 4 = Samples per chirp (280) — real, normalized float [-1, 1]
%
%  SCENARIO: Open environment, teammate moving hand in front of radar
%    - Target range: ~0.2 to 1.5 m (near field, hand motion)
%    - Data is already float centered at 0 — NO ADC offset needed
%    - Real-valued -> one-sided FFT
%    - Clutter removal essential to isolate hand from static background
%
%  Config: 61-63 GHz | BW=2 GHz | fs=1.006 MHz | frame_dt=0.0773 s
%  Range resolution = c/(2*B) = 0.075 m
% =========================================================================

clc; close all;

%% ========== USER SETTINGS — EDIT HERE ==================================
folder    = "C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\fixed_runs\20260224_163700_fixed_corridor";

use_rx    = 1;           % Which RX to use (1, 2, or 3)
nfft_r    = 512;         % Range FFT size (zero-padded)
nfft_d    = 128;         % Doppler FFT size = num_chirps_per_frame
r_gate    = [0.1 1.5];   % HAND MOTION: search 0.1-1.5 m (near field)
chunk_size = 200;        % Frames per chunk
do_clutter_remove = true;% MUST be true for hand motion — removes static background

% Output files
outRT    = fullfile(folder, "RT_full.png");
outVT    = fullfile(folder, "VT_full.png");
outRP    = fullfile(folder, "range_profile_mean.png");
outPower = fullfile(folder, "hand_power_plot.png");
outCSV   = fullfile(folder, "hand_power_timeseries.csv");
outMatRT = fullfile(folder, "RT_matrix.mat");
outMatVT = fullfile(folder, "VT_matrix.mat");
%% =======================================================================

fprintf("=== RT/VT Processor — Hand Motion (Raspberry Pi) ===\n");
fprintf("Folder: %s\n\n", folder);

mat_path = fullfile(folder, "radar.mat");
cfg_path = fullfile(folder, "config.json");
if ~isfile(mat_path); error("Missing: %s", mat_path); end
if ~isfile(cfg_path); error("Missing: %s", cfg_path); end

%% --- Load config --------------------------------------------------------
cfg  = jsondecode(fileread(cfg_path));
s    = cfg.device_config.fmcw_single_shape;

fs        = double(s.sample_rate_Hz);           % 1.006e6 Hz
f_start   = double(s.start_frequency_Hz);       % 61e9 Hz
f_end     = double(s.end_frequency_Hz);         % 63e9 Hz
PRI       = double(s.chirp_repetition_time_s);  % 0.0003 s
frame_dt  = double(s.frame_repetition_time_s);  % 0.0773 s
n_chirps  = double(s.num_chirps_per_frame);     % 128
n_samp    = double(s.num_samples_per_chirp);    % 280
n_rx      = numel(s.rx_antennas);              % 3

fprintf("Config:\n");
fprintf("  Freq:     %.0f - %.0f GHz  (BW = %.1f GHz)\n", ...
    f_start/1e9, f_end/1e9, (f_end-f_start)/1e9);
fprintf("  fs:       %.3f MHz | Chirps/frame: %d | Samples/chirp: %d | RX: %d\n", ...
    fs/1e6, n_chirps, n_samp, n_rx);
fprintf("  Frame dt: %.4f s (%.2f fps)\n\n", frame_dt, 1/frame_dt);

%% --- Build axes ---------------------------------------------------------
c      = 299792458;
B      = f_end - f_start;        % 2 GHz
Tc     = n_samp / fs;            % chirp duration
slope  = B / Tc;

% One-sided range axis (real FFT)
n_pos  = floor(nfft_r/2) + 1;
f_b    = (0:n_pos-1) * (fs / nfft_r);
r_axis = (c * f_b) / (2 * slope);

% Velocity axis
fc     = (f_start + f_end) / 2;  % 62 GHz
lambda = c / fc;
PRF    = 1 / PRI;
fd     = ((-nfft_d/2):(nfft_d/2-1)) * (PRF / nfft_d);
v_axis = (fd * lambda) / 2;

fprintf("Axes:\n");
fprintf("  Range res:  %.4f m | Max range: %.3f m\n", c/(2*B), max(r_axis));
fprintf("  Velocity:   [%.2f, %.2f] m/s\n", min(v_axis), max(v_axis));
fprintf("  Hand search gate: [%.2f, %.2f] m\n\n", r_gate(1), r_gate(2));

%% --- Inspect .mat -------------------------------------------------------
info = whos('-file', mat_path);
vi   = info(strcmp({info.name}, 'radar_data'));
sz   = vi.size;
F_total = sz(1);   % 774
fprintf("radar_data: [%s]  %s  %.1f MB\n", num2str(sz), vi.class, vi.bytes/1e6);
fprintf("Total frames: %d  |  %.1f s  |  %.2f min\n\n", ...
    F_total, F_total*frame_dt, F_total*frame_dt/60);

if use_rx < 1 || use_rx > n_rx
    error("use_rx=%d out of range. Valid: 1 to %d", use_rx, n_rx);
end

%% --- Pre-allocate -------------------------------------------------------
RT_all    = zeros(F_total, n_pos,  'single');
VT_all    = zeros(F_total, nfft_d, 'single');
power_all = zeros(F_total, 1,      'single');
range_all = zeros(F_total, 1,      'single'); % tracked hand range per frame
mean_prof = zeros(1, n_pos,        'double');

%% --- Load data ----------------------------------------------------------
fprintf("Loading radar.mat...\n"); tic;
S   = load(mat_path, 'radar_data');
raw = S.radar_data;   % [F x RX x Chirps x Samples]  single
clear S;
fprintf("Loaded in %.1f s\n\n", toc);

%% --- Hann windows -------------------------------------------------------
w_r = reshape(hann(n_samp,   'periodic'), 1, 1, []);  % 1 x 1 x n_samp
w_d = reshape(hann(n_chirps, 'periodic'), 1, [], 1);  % 1 x n_chirps x 1

n_chunks = ceil(F_total / chunk_size);

%% -----------------------------------------------------------------------
%  PASS 1: Range FFT -> RT + mean range profile
%% -----------------------------------------------------------------------
fprintf("Pass 1/2: Range-Time (RT)...\n");

for ch = 1:n_chunks
    f1 = (ch-1)*chunk_size + 1;
    f2 = min(ch*chunk_size, F_total);

    % Extract chosen RX: [Fc x Chirps x Samples]
    % raw layout: [F x RX x Chirps x Samples]
    chunk = squeeze(raw(f1:f2, use_rx, :, :));  % Fc x n_chirps x n_samp

    % Already float centered at 0 — use directly
    x = single(chunk);

    % Apply range Hann window
    x = x .* w_r;

    % Real FFT — keep one-sided
    Xr_full = fft(x, nfft_r, 3);
    Xr      = Xr_full(:, :, 1:n_pos);          % Fc x n_chirps x n_pos

    % Mean over chirps -> range profile
    RP       = squeeze(mean(abs(Xr), 2));       % Fc x n_pos
    RT_chunk = 20*log10(RP + 1e-12);

    RT_all(f1:f2, :) = RT_chunk;
    mean_prof = mean_prof + double(sum(RT_chunk, 1));

    fprintf("  Pass1 chunk %3d/%3d | Frames %4d-%4d\r", ch, n_chunks, f1, f2);
end
fprintf("\nPass 1 done.\n\n");
mean_prof = mean_prof / F_total;

%% --- Find hand/target peak in r_gate ------------------------------------
r_idx = find(r_axis >= r_gate(1) & r_axis <= r_gate(2));
if isempty(r_idx)
    error("r_gate [%.2f %.2f] has no bins. Max range = %.2f m.", ...
        r_gate(1), r_gate(2), max(r_axis));
end

% For hand motion: use the peak of the CLUTTER-REMOVED mean profile
% First compute mean clutter-removed profile
mean_prof_cr = zeros(1, n_pos, 'double');
for ch = 1:n_chunks
    f1 = (ch-1)*chunk_size + 1;
    f2 = min(ch*chunk_size, F_total);
    chunk  = squeeze(raw(f1:f2, use_rx, :, :));
    x      = single(chunk) .* w_r;
    Xr_f   = fft(x, nfft_r, 3);
    Xr     = Xr_f(:, :, 1:n_pos);
    Xr_cr  = Xr - mean(Xr, 2);                 % clutter removed
    RP_cr  = squeeze(mean(abs(Xr_cr), 2));
    mean_prof_cr = mean_prof_cr + double(sum(20*log10(RP_cr + 1e-12), 1));
    fprintf("  Profile chunk %3d/%3d\r", ch, n_chunks);
end
fprintf("\n");
mean_prof_cr = mean_prof_cr / F_total;

[~, lp]  = max(mean_prof_cr(r_idx));
pk_bin   = r_idx(lp);
pk_range = r_axis(pk_bin);
fprintf("\n>>> Hand/target peak (clutter removed): %.3f m (bin %d) <<<\n\n", ...
    pk_range, pk_bin);

halfw = 4;
rr    = max(1, pk_bin-halfw) : min(n_pos, pk_bin+halfw);

%% -----------------------------------------------------------------------
%  PASS 2: Doppler FFT -> VT + per-frame hand tracking
%% -----------------------------------------------------------------------
fprintf("Pass 2/2: Velocity-Time (VT) + hand tracking @ %.3f m...\n", pk_range);

for ch = 1:n_chunks
    f1 = (ch-1)*chunk_size + 1;
    f2 = min(ch*chunk_size, F_total);

    chunk = squeeze(raw(f1:f2, use_rx, :, :));
    x     = single(chunk) .* w_r;

    % Range FFT (one-sided)
    Xr_full = fft(x, nfft_r, 3);
    Xr      = Xr_full(:, :, 1:n_pos);

    % Clutter removal — CRITICAL for hand motion
    if do_clutter_remove
        Xr = Xr - mean(Xr, 2);
    end

    % Doppler FFT
    Xd = fftshift(fft(Xr .* w_d, nfft_d, 2), 2);  % Fc x nfft_d x n_pos

    % VT: sum over focused range bins around hand peak
    VT_chunk = squeeze(sum(abs(Xd(:, :, rr)), 3));  % Fc x nfft_d
    VT_all(f1:f2, :) = 20*log10(single(VT_chunk) + 1e-12);

    % Per-frame hand range tracking (strongest bin in r_gate)
    RT_cr_chunk = 20*log10(squeeze(mean(abs(Xr), 2)) + 1e-12); % Fc x n_pos
    for fi = 1:(f2-f1+1)
        [~, best] = max(RT_cr_chunk(fi, r_idx));
        range_all(f1+fi-1) = r_axis(r_idx(best));
    end

    % Power at tracked peak bin
    power_all(f1:f2) = RT_all(f1:f2, pk_bin);

    fprintf("  Pass2 chunk %3d/%3d | Frames %4d-%4d\r", ch, n_chunks, f1, f2);
end
fprintf("\nPass 2 done.\n\n");
clear raw;

%% --- Time axis ----------------------------------------------------------
t_axis = single((0:F_total-1)' * frame_dt);
t_s    = t_axis;
fprintf("Duration: %.1f s (%.2f min)\n\n", t_s(end), t_s(end)/60);

%% -----------------------------------------------------------------------
%  PLOTS
%% -----------------------------------------------------------------------
fprintf("Saving plots...\n");

r_disp = find(r_axis >= 0.0 & r_axis <= r_gate(2) + 0.5);

% -- RT (clutter-removed, near-field) --
fig = figure("Visible","off","Position",[50 50 1600 550]);
imagesc(t_s, r_axis(r_disp), double(RT_all(:, r_disp))'); axis xy;
xlabel("Time (s)"); ylabel("Range (m)");
title(sprintf("Range-Time (RT) | Hand Motion | Peak @ %.3f m | RX%d | %.1f s", ...
    pk_range, use_rx, t_s(end)));
colorbar; colormap("jet");
hold on;
plot(t_s, range_all, 'w-', 'LineWidth', 1.2);   % tracked hand range overlay
yline(pk_range,'w--','LineWidth',1,'Label',sprintf('Mean peak %.3f m',pk_range));
legend({'Tracked range'},'Location','northeast','TextColor','w');
pclim(gca, RT_all(:, r_disp));
exportgraphics(fig, outRT, "Resolution",200); close(fig);
fprintf("  RT:    %s\n", outRT);

% -- VT --
fig = figure("Visible","off","Position",[50 50 1600 550]);
imagesc(t_s, v_axis, double(VT_all)'); axis xy;
xlabel("Time (s)"); ylabel("Velocity (m/s)");
title(sprintf("Velocity-Time (VT) | Hand Motion | @ %.3f m | Clutter Removed | RX%d", ...
    pk_range, use_rx));
colorbar; colormap("jet");
yline(0,'w--','LineWidth',1);
pclim(gca, VT_all);
exportgraphics(fig, outVT, "Resolution",200); close(fig);
fprintf("  VT:    %s\n", outVT);

% -- Mean range profile (both raw and clutter-removed) --
fig = figure("Visible","off","Position",[800 400 1000 550]);
plot(r_axis, mean_prof,    'b',  'LineWidth', 1.5); hold on; grid on;
plot(r_axis, mean_prof_cr, 'r',  'LineWidth', 1.5);
xline(pk_range,'k--','LineWidth',2,'Label',sprintf('Peak %.3f m',pk_range));
xline(r_gate(1),'g:','LineWidth',1.5,'Label',sprintf('Gate %.1fm',r_gate(1)));
xline(r_gate(2),'g:','LineWidth',1.5,'Label',sprintf('Gate %.1fm',r_gate(2)));
xlabel("Range (m)"); ylabel("Mean Power (dB)");
title(sprintf("Mean Range Profile | Hand Motion | RX%d | %d frames", use_rx, F_total));
xlim([0 r_gate(2)+0.5]);
legend({'Raw','Clutter Removed','Peak','Gate'},'Location','northeast');
exportgraphics(fig, outRP, "Resolution",200); close(fig);
fprintf("  RP:    %s\n", outRP);

% -- Hand power time series --
fig = figure("Visible","off","Position",[50 50 1600 400]);
yyaxis left
plot(t_s, double(power_all), 'b', 'LineWidth', 0.8);
ylabel("Power (dB)");
yyaxis right
plot(t_s, double(range_all), 'r', 'LineWidth', 0.8);
ylabel("Tracked Range (m)");
xlabel("Time (s)"); grid on;
title(sprintf("Hand Power & Range vs Time | Peak @ %.3f m | %.1f s total", ...
    pk_range, t_s(end)));
legend({'Power (dB)','Tracked Range (m)'},'Location','northeast');
xlim([0 t_s(end)]);
exportgraphics(fig, outPower, "Resolution",200); close(fig);
fprintf("  Power: %s\n", outPower);

% -- CSV --
T = table(double(t_axis), double(power_all), double(range_all), ...
    'VariableNames', {'t_s','hand_power_dB','tracked_range_m'});
writetable(T, outCSV);
fprintf("  CSV:   %s\n", outCSV);

% -- Save .mat --
r_ax_gate = r_axis(r_idx); %#ok<NASGU>
save(outMatRT, 'RT_all','t_axis','r_axis','r_ax_gate', ...
    'pk_range','pk_bin','mean_prof','mean_prof_cr','range_all','-v7.3');
save(outMatVT, 'VT_all','t_axis','v_axis','pk_range','-v7.3');
fprintf("  MatRT: %s\n  MatVT: %s\n", outMatRT, outMatVT);

fprintf("\n=== ALL DONE ===\n");
fprintf("Hand peak: %.3f m | Duration: %.1f s\n", pk_range, t_s(end));
end


%% =========================================================================
%  Auto color limits: 5th-95th percentile
%% =========================================================================
function pclim(ax, data)
    flat = double(data(:));
    flat = flat(isfinite(flat));
    clim(ax, [prctile(flat,5), prctile(flat,95)]);
end