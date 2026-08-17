function door_rt_vt_enhanced()
% =========================================================================
%  ENHANCED RT & VT PROCESSOR — BGT60TR13C
%
%  DATA FORMAT CONFIRMED:
%    radar_data: [69333 x 1 x 64 x 64]  uint16
%    - 64 samples per chirp are REAL ADC samples (NOT IQ interleaved)
%    - Values centered ~2048 (12-bit ADC midpoint)
%    - Must subtract 2048, then real FFT, keep positive half
%    - Effective n_complex = 64 real -> 33 useful FFT bins (one-sided)
%
%  With correct treatment:
%    Max range = c * fs / (4 * slope) using real FFT = ~0.87 m
%    Radar placed at 0.61 m from door -> door peak expected ~0.61 m
% =========================================================================

clc; close all;

%% ========== USER SETTINGS ==============================================
folder = "C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Second_Session20260226-131652\RadarIfxAvian_00";

cfg_path  = fullfile(folder, "config.json");
mat_path  = fullfile(folder, "radar.mat");

nfft_r     = 256;        % Zero-pad range FFT for smoother profile (real FFT)
nfft_d     = 64;         % Doppler FFT size = num_chirps_per_frame
r_gate     = [0.3 0.85]; % Range gate: radar is at 0.61 m, search 0.3-0.85 m
chunk_size = 500;        % Frames per chunk (reduce to 200 if RAM errors)
do_clutter_remove = true;
ADC_OFFSET = 2048;       % 12-bit ADC midpoint to subtract (confirmed from data)

outRT    = fullfile(folder, "RT_full.png");
outVT    = fullfile(folder, "VT_full.png");
outRP    = fullfile(folder, "range_profile_mean.png");
outPower = fullfile(folder, "door_power_plot.png");
outCSV   = fullfile(folder, "door_power_timeseries.csv");
outMatRT = fullfile(folder, "RT_matrix.mat");
outMatVT = fullfile(folder, "VT_matrix.mat");
%% =======================================================================

fprintf("=== Enhanced RT/VT Processor (Real ADC / Corrected) ===\n");
fprintf("Folder: %s\n\n", folder);

if ~isfile(mat_path); error("Missing: %s", mat_path); end
if ~isfile(cfg_path); error("Missing: %s", cfg_path); end

%% --- Load config --------------------------------------------------------
cfg = jsondecode(fileread(cfg_path));
s   = cfg.device_config.fmcw_single_shape;

fs       = double(s.sample_rate_Hz);          % 2e6 Hz
f_start  = double(s.start_frequency_Hz);      % 58e9 Hz
f_end    = double(s.end_frequency_Hz);        % 63.5e9 Hz
PRI      = double(s.chirp_repetition_time_s); % 0.000591 s
frame_dt = double(s.frame_repetition_time_s); % 0.0773 s
n_chirps = double(s.num_chirps_per_frame);    % 64
n_samp   = double(s.num_samples_per_chirp);   % 64  <- all REAL samples

fprintf("Config:\n");
fprintf("  Freq:     %.0f - %.0f GHz  (BW = %.1f GHz)\n", f_start/1e9, f_end/1e9, (f_end-f_start)/1e9);
fprintf("  fs:       %.0f MHz\n", fs/1e6);
fprintf("  Chirps/frame: %d  |  Samples/chirp: %d (REAL)\n", n_chirps, n_samp);
fprintf("  Frame dt: %.4f s  (%.2f fps)\n\n", frame_dt, 1/frame_dt);

%% --- Build CORRECTED axes (real ADC, one-sided FFT) --------------------
c      = 299792458;
B      = f_end - f_start;          % 5.5 GHz bandwidth
Tc     = n_samp / fs;              % chirp duration = 64/2e6 = 32 us
slope  = B / Tc;                   % 5.5e9 / 32e-6 = 171.875 THz/s

% Real FFT: n_samp points -> nfft_r/2+1 one-sided bins
% Beat frequency for range bin k: f_b(k) = k * fs / nfft_r
% Range: r = c * f_b / (2 * slope)
% Max unambiguous range (real): r_max = c * fs / (4 * slope)
n_pos   = floor(nfft_r/2) + 1;    % number of positive-frequency bins
f_b     = (0:n_pos-1) * (fs / nfft_r);
r_axis  = (c * f_b) / (2 * slope);

r_max_theory = c * fs / (4 * slope);
fprintf("CORRECTED Range axis:\n");
fprintf("  Max unambiguous range = %.3f m\n", r_max_theory);
fprintf("  Range resolution      = %.4f m\n", c / (2 * B));
fprintf("  Radar placed at 0.61 m -> expect peak ~bin %d (%.3f m)\n\n", ...
    round(0.61 / (c/(2*B))), round(0.61/(c/(2*B))) * (c/(2*B)));

% Velocity axis (Doppler — same as before, uses slow-time across chirps)
fc     = (f_start + f_end) / 2;   % 60.75 GHz center
lambda = c / fc;                   % ~4.94 mm wavelength
PRF    = 1 / PRI;
fd     = ((-nfft_d/2):(nfft_d/2-1)) * (PRF / nfft_d);
v_axis = (fd * lambda) / 2;

fprintf("Velocity axis: [%.2f, %.2f] m/s\n\n", min(v_axis), max(v_axis));

%% --- Inspect .mat -------------------------------------------------------
info     = whos('-file', mat_path);
vi       = info(strcmp({info.name}, 'radar_data'));
sz       = vi.size;
F_total  = sz(1);   % 69333

fprintf("radar_data: [%s]  %s  %.1f MB\n", num2str(sz), vi.class, vi.bytes/1e6);
fprintf("Total frames: %d  |  %.1f min  |  %.2f hr\n\n", ...
    F_total, F_total*frame_dt/60, F_total*frame_dt/3600);

%% --- Pre-allocate -------------------------------------------------------
RT_all    = zeros(F_total, n_pos, 'single');
VT_all    = zeros(F_total, nfft_d, 'single');
power_all = zeros(F_total, 1, 'single');
mean_prof = zeros(1, n_pos, 'double');

%% --- Load data ----------------------------------------------------------
fprintf("Loading radar.mat (%.0f MB)...\n", vi.bytes/1e6); tic;
S   = load(mat_path, 'radar_data');
raw = S.radar_data;   % [F x 1 x 64 x 64]  uint16
clear S;
fprintf("Loaded in %.1f s\n\n", toc);

%% --- Windows ------------------------------------------------------------
% Range: Hann over n_samp real samples
w_r = reshape(hann(n_samp, 'periodic'), 1, 1, []);   % 1 x 1 x n_samp
% Doppler: Hann over n_chirps chirps
w_d = reshape(hann(n_chirps, 'periodic'), 1, [], 1); % 1 x n_chirps x 1

n_chunks = ceil(F_total / chunk_size);

%% -----------------------------------------------------------------------
%  PASS 1: Real Range FFT -> RT + mean range profile
%% -----------------------------------------------------------------------
fprintf("Pass 1/2: Range-Time (RT)...\n");

for ch = 1:n_chunks
    f1 = (ch-1)*chunk_size + 1;
    f2 = min(ch*chunk_size, F_total);

    % Extract [Fc x n_chirps x n_samp], remove RX dim
    chunk = squeeze(raw(f1:f2, 1, :, :));   % Fc x n_chirps x n_samp

    % Convert uint16 to real centered signal
    x = single(chunk) - ADC_OFFSET;         % Fc x n_chirps x n_samp  (real)

    % Apply range window
    x = x .* w_r;                           % Fc x n_chirps x n_samp

    % Real FFT -> keep only positive frequencies (one-sided)
    Xr_full = fft(x, nfft_r, 3);            % Fc x n_chirps x nfft_r
    Xr      = Xr_full(:, :, 1:n_pos);       % Fc x n_chirps x n_pos

    % Mean over chirps -> range profile
    RP       = squeeze(mean(abs(Xr), 2));   % Fc x n_pos
    RT_chunk = 20*log10(RP + 1e-12);

    RT_all(f1:f2, :) = RT_chunk;
    mean_prof = mean_prof + double(sum(RT_chunk, 1));

    fprintf("  Pass1 chunk %3d/%3d | Frames %6d-%6d\r", ch, n_chunks, f1, f2);
end
fprintf("\nPass 1 done.\n\n");
mean_prof = mean_prof / F_total;

%% --- Find door peak in r_gate -------------------------------------------
r_idx = find(r_axis >= r_gate(1) & r_axis <= r_gate(2));
if isempty(r_idx)
    error("r_gate [%.2f %.2f] has no bins. Max range = %.3f m. Adjust r_gate.", ...
        r_gate(1), r_gate(2), max(r_axis));
end

[~, lp]  = max(mean_prof(r_idx));
pk_bin   = r_idx(lp);
pk_range = r_axis(pk_bin);
fprintf(">>> Door/target peak: %.3f m (bin %d) <<<\n", pk_range, pk_bin);
fprintf("    (Radar placed at 0.61 m — offset = %.3f m)\n\n", abs(pk_range - 0.61));

halfw = 4;
rr    = max(1, pk_bin-halfw) : min(n_pos, pk_bin+halfw);

%% -----------------------------------------------------------------------
%  PASS 2: Doppler FFT -> VT focused on door range
%% -----------------------------------------------------------------------
fprintf("Pass 2/2: Velocity-Time (VT) @ %.3f m...\n", pk_range);

for ch = 1:n_chunks
    f1 = (ch-1)*chunk_size + 1;
    f2 = min(ch*chunk_size, F_total);

    chunk = squeeze(raw(f1:f2, 1, :, :));
    x     = single(chunk) - ADC_OFFSET;
    x     = x .* w_r;

    % Range FFT (one-sided)
    Xr_full = fft(x, nfft_r, 3);
    Xr      = Xr_full(:, :, 1:n_pos);      % Fc x n_chirps x n_pos

    % Clutter removal: subtract mean across chirps (slow-time mean)
    if do_clutter_remove
        Xr = Xr - mean(Xr, 2);
    end

    % Doppler FFT across chirps (slow-time)
    Xd = fftshift(fft(Xr .* w_d, nfft_d, 2), 2);  % Fc x nfft_d x n_pos

    % Sum magnitude over focused range bins around door peak
    VT_chunk = squeeze(sum(abs(Xd(:, :, rr)), 3));  % Fc x nfft_d
    VT_all(f1:f2, :) = 20*log10(single(VT_chunk) + 1e-12);

    % Door power from RT at peak bin
    power_all(f1:f2) = RT_all(f1:f2, pk_bin);

    fprintf("  Pass2 chunk %3d/%3d | Frames %6d-%6d\r", ch, n_chunks, f1, f2);
end
fprintf("\nPass 2 done.\n\n");
clear raw;

%% --- Time axes ----------------------------------------------------------
t_axis = single((0:F_total-1)' * frame_dt);
t_min  = t_axis / 60;
fprintf("Duration: %.1f min (%.2f hr)\n\n", t_min(end), t_min(end)/60);

%% -----------------------------------------------------------------------
%  PLOTS
%% -----------------------------------------------------------------------
fprintf("Saving plots...\n");

% Range gate indices for display
r_disp = find(r_axis >= 0.0 & r_axis <= r_gate(2));

% -- RT --
fig = figure("Visible","off","Position",[50 50 1800 550]);
imagesc(t_min, r_axis(r_disp), double(RT_all(:, r_disp))'); axis xy;
xlabel("Time (min)"); ylabel("Range (m)");
title(sprintf("Range-Time (RT) | Door peak @ %.3f m (placed @ 0.61 m) | %d frames | %.1f min", ...
    pk_range, F_total, t_min(end)));
colorbar; colormap("jet");
yline(pk_range, 'w--', 'LineWidth', 1.5, 'Label', sprintf('%.3f m', pk_range));
pclim(gca, RT_all(:, r_disp));
exportgraphics(fig, outRT, "Resolution", 200); close(fig);
fprintf("  RT:    %s\n", outRT);

% -- VT --
fig = figure("Visible","off","Position",[50 50 1800 550]);
imagesc(t_min, v_axis, double(VT_all)'); axis xy;
xlabel("Time (min)"); ylabel("Velocity (m/s)");
if do_clutter_remove
    title(sprintf("Velocity-Time (VT) | %.3f m | Clutter Removed | Real ADC corrected", pk_range));
else
    title(sprintf("Velocity-Time (VT) | %.3f m | Raw", pk_range));
end
colorbar; colormap("jet");
yline(0, 'w--', 'LineWidth', 1);
pclim(gca, VT_all);
exportgraphics(fig, outVT, "Resolution", 200); close(fig);
fprintf("  VT:    %s\n", outVT);

% -- Mean range profile --
fig = figure("Visible","off","Position",[800 400 1000 550]);
plot(r_axis, mean_prof, 'b', 'LineWidth', 1.5); grid on; hold on;
xline(pk_range, 'r--', 'LineWidth', 2, 'Label', sprintf('Peak %.3f m', pk_range));
xline(0.61,     'g--', 'LineWidth', 2, 'Label', 'Placed @ 0.61 m');
xlabel("Range (m)"); ylabel("Mean Power (dB)");
title("Mean Range Profile (all frames) — Real ADC corrected");
xlim([0 max(r_axis)]);
legend({'Profile','Detected peak','Physical placement'},'Location','northeast');
exportgraphics(fig, outRP, "Resolution", 200); close(fig);
fprintf("  RP:    %s\n", outRP);

% -- Door power time series --
fig = figure("Visible","off","Position",[50 50 1800 400]);
plot(t_min, double(power_all), 'b', 'LineWidth', 0.5); grid on;
xlabel("Time (min)"); ylabel("Power (dB)");
title(sprintf("Door Power @ %.3f m | %.1f min total | Real ADC corrected", pk_range, t_min(end)));
xlim([0 t_min(end)]);
exportgraphics(fig, outPower, "Resolution", 200); close(fig);
fprintf("  Power: %s\n", outPower);

% -- CSV --
T = table(double(t_axis), double(t_min), double(power_all), ...
    'VariableNames', {'t_s','t_min','door_power_dB'});
writetable(T, outCSV);
fprintf("  CSV:   %s\n", outCSV);

% -- Save .mat --
r_ax_gate = r_axis(r_idx); %#ok<NASGU>
save(outMatRT, 'RT_all','t_axis','t_min','r_axis','r_ax_gate', ...
    'pk_range','pk_bin','mean_prof', '-v7.3');
save(outMatVT, 'VT_all','t_axis','t_min','v_axis','pk_range', '-v7.3');
fprintf("  MatRT: %s\n  MatVT: %s\n", outMatRT, outMatVT);

fprintf("\n=== ALL DONE ===\n");
fprintf("Expected door range: 0.61 m | Detected: %.3f m | Error: %.3f m\n", ...
    pk_range, abs(pk_range-0.61));
end


%% =========================================================================
%  Auto color limits: 5th-95th percentile
%% =========================================================================
function pclim(ax, data)
    flat = double(data(:));
    flat = flat(isfinite(flat));
    clim(ax, [prctile(flat, 5), prctile(flat, 95)]);
end
