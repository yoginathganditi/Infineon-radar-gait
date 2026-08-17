function report = run_shoe_mounted(recording_folder, varargin)
% RUN_SHOE_MOUNTED  Shoe-mounted radar gait analysis pipeline
%                   with AUTO-ZOOM: finds best 2-second window with 3-5 clean steps
%                   Publication-quality figure output (updated)
%
% Usage:
%   report = run_shoe_mounted(recording_folder)
%   report = run_shoe_mounted(recording_folder, 'zoom_window_s', 2.0, ...)

    p = inputParser;
    addRequired(p, 'recording_folder', @ischar);
    addParameter(p, 'frame_dt',            [],           @isnumeric);
    addParameter(p, 'r_gate',              [0.10, 1.20], @isnumeric);
    addParameter(p, 'show',                true,         @islogical);
    addParameter(p, 'gt_steps',            [],           @isnumeric);
    addParameter(p, 'min_gap_s',           0.5,          @isnumeric);
    addParameter(p, 'use_segments',        true,         @islogical);
    addParameter(p, 'segments_mode',       'hysteresis', @ischar);
    addParameter(p, 'segment_pad_s',       0.25,         @isnumeric);
    addParameter(p, 'step_mode',           'hybrid',     @ischar);
    addParameter(p, 'min_step_height_mps', 0.20,         @isnumeric);
    addParameter(p, 'height_prc',          10,           @isnumeric);
    addParameter(p, 'save_separate_plots', true,         @islogical);
    addParameter(p, 'zoom_time_range',     [],           @isnumeric);
    addParameter(p, 'zoom_window_s',       2.0,          @isnumeric);
    addParameter(p, 'zoom_min_steps',      3,            @isnumeric);
    addParameter(p, 'zoom_max_steps',      6,            @isnumeric);
    addParameter(p, 'zoom_regularity_thr', 0.35,         @isnumeric);
    addParameter(p, 'rt_vmin_percentile',  35.0,         @isnumeric);
    addParameter(p, 'vt_vmin_percentile',  8.0,          @isnumeric);
    addParameter(p, 'vmax_percentile',     99.7,         @isnumeric);
    addParameter(p, 'smooth_sigma_y',      0.3,          @isnumeric);
    addParameter(p, 'smooth_sigma_x',      0.3,          @isnumeric);
    addParameter(p, 'rt_interpolation',    'bilinear',   @ischar);
    addParameter(p, 'vt_interpolation',    'none',       @ischar);
    addParameter(p, 'v_plot_lim',          [-3.8, 3.8],  @isnumeric);
    addParameter(p, 'dpi_png',             600,          @isnumeric);

    parse(p, recording_folder, varargin{:});

    recording_folder    = char(recording_folder);
    frame_dt            = p.Results.frame_dt;
    r_gate              = p.Results.r_gate;
    show                = p.Results.show;
    use_segments        = p.Results.use_segments;
    segments_mode       = p.Results.segments_mode;
    segment_pad_s       = p.Results.segment_pad_s;
    step_mode           = p.Results.step_mode;
    min_step_height_mps = p.Results.min_step_height_mps;
    height_prc          = p.Results.height_prc;
    save_sep_plots      = p.Results.save_separate_plots;
    zoom_time_range     = p.Results.zoom_time_range;
    zoom_window_s       = p.Results.zoom_window_s;
    zoom_min_steps      = p.Results.zoom_min_steps;
    zoom_max_steps      = p.Results.zoom_max_steps;
    zoom_regularity_thr = p.Results.zoom_regularity_thr;
    dpi_png             = p.Results.dpi_png;
    v_plot_lim          = p.Results.v_plot_lim;
    rt_vmin_prc         = p.Results.rt_vmin_percentile;
    vt_vmin_prc         = p.Results.vt_vmin_percentile;
    vmax_prc            = p.Results.vmax_percentile;

    fprintf('\n=== SHOE-MOUNTED RADAR GAIT ANALYSIS ===\n');
    fprintf('Recording folder: %s\n', recording_folder);
    fprintf('Range gate: [%.2f, %.2f] m\n\n', r_gate(1), r_gate(2));

    % ------------------------------------------------------------------ %
    % 1. Load data
    % ------------------------------------------------------------------ %
    fprintf('1. Loading data...\n');
    [adc, cfg_json, ~] = load_recording(recording_folder, [128, 3, 64]);
    cfg = derive_cfg_params(cfg_json);

    if isempty(frame_dt)
        frame_dt = cfg.frame_T;
    end

    % ------------------------------------------------------------------ %
    % 2. RD / RT / VT maps
    % ------------------------------------------------------------------ %
    fprintf('2. Computing RD/RT/VT maps...\n');
    [rd, rt] = compute_rd_rt(adc, cfg, 256, cfg.num_chirps);

    r_axis = make_range_axis(cfg, 256);
    v_axis = make_velocity_axis(cfg, cfg.num_chirps);
    r_idx  = range_gate_indices(r_axis, r_gate(1), r_gate(2));

    % ------------------------------------------------------------------ %
    % 3. Range centroid
    % ------------------------------------------------------------------ %
    fprintf('3. Computing range centroid...\n');
    rc_m = range_centroid(rt, r_axis, r_idx);

    % ------------------------------------------------------------------ %
    % 4. VT + toe envelope
    % ------------------------------------------------------------------ %
    fprintf('4. Computing VT map & toe envelope...\n');
    vt = vt_from_rd_static(rd, r_idx, 'sum');
    [toe, ~] = toe_envelope(vt, v_axis);

    % ------------------------------------------------------------------ %
    % 5. Walking segments
    % ------------------------------------------------------------------ %
    fprintf('5. Finding walking segments...\n');
    [walk_segments, thr_on, thr_off] = find_walking_segments(toe, frame_dt, ...
        'segments_mode', segments_mode, 'walk_k', 0.15, ...
        'min_walk_s', 0.8, 'min_gap_s', p.Results.min_gap_s);

    % ------------------------------------------------------------------ %
    % 6. Step detection
    % ------------------------------------------------------------------ %
    fprintf('6. Detecting steps...\n');
    [peaks_all, height_thr_used, prom_used] = detect_steps_from_toe(toe, frame_dt, ...
        'prom_k', 0.02, 'prom_floor', 0.010, ...
        'height_prc', height_prc, ...
        'min_step_toe_mps', min_step_height_mps, ...
        'min_step_distance_s', 0.18);

    if use_segments && ~isempty(walk_segments)
        walking_mask = build_walking_mask(length(toe), walk_segments, frame_dt, segment_pad_s);
    else
        walking_mask = true(size(toe));
    end

    peaks_walk = peaks_all(walking_mask(peaks_all));

    if strcmp(step_mode, 'walking')
        steps_for_stats     = peaks_walk;
        steps_for_plot_all  = [];
        steps_for_plot_used = steps_for_stats;
    elseif strcmp(step_mode, 'all')
        steps_for_stats     = peaks_all;
        steps_for_plot_all  = peaks_all;
        steps_for_plot_used = peaks_all;
    else % hybrid
        steps_for_stats     = peaks_walk;
        steps_for_plot_all  = peaks_all;
        steps_for_plot_used = steps_for_stats;
    end

    % ------------------------------------------------------------------ %
    % 7. AUTO-ZOOM
    % ------------------------------------------------------------------ %
    if isempty(zoom_time_range)
        fprintf('7. Auto-selecting zoom window (%.1f s, %d-%d steps)...\n', ...
                zoom_window_s, zoom_min_steps, zoom_max_steps);
        zoom_time_range = auto_select_zoom_window_shoe( ...
            steps_for_plot_used, toe, frame_dt, walk_segments, ...
            zoom_window_s, zoom_min_steps, zoom_max_steps, zoom_regularity_thr);

        if ~isempty(zoom_time_range)
            fprintf('   Auto-zoom selected: [%.2f, %.2f] s\n', zoom_time_range(1), zoom_time_range(2));
        else
            fprintf('   Auto-zoom: no suitable window found (will skip zoom plots).\n');
        end
    else
        fprintf('7. Using manual zoom_time_range: [%.2f, %.2f] s\n', zoom_time_range(1), zoom_time_range(2));
    end

    % ------------------------------------------------------------------ %
    % 8. Step table
    % ------------------------------------------------------------------ %
    fprintf('8. Computing step table...\n');
    step_rows = compute_step_table(steps_for_stats, rc_m, v_axis, vt, frame_dt);

    % ------------------------------------------------------------------ %
    % 9. Statistics
    % ------------------------------------------------------------------ %
    fprintf('9. Computing statistics...\n');
    total_steps_all     = length(peaks_all);
    total_steps_walking = length(peaks_walk);
    total_steps_used    = length(steps_for_stats);
    total_duration      = length(toe) * frame_dt;

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
        if length(s) >= 2, step_times = diff(s) * frame_dt;
        else, step_times = []; end
        if length(s) >= 3, stride_times = (s(3:end) - s(1:end-2)) * frame_dt;
        else, stride_times = []; end
    end

    [mean_step_time,   step_time_cv]   = mean_and_cv(step_times);
    [mean_stride_time, stride_time_cv] = mean_and_cv(stride_times);

    v_app_vals   = cellfun(@(r) r.v_app,      step_rows);
    v_sep_vals   = cellfun(@(r) r.v_sep,      step_rows);
    d_align_vals = cellfun(@(r) r.d_align_cm, step_rows);

    peak_vapp_mean  = mean(v_app_vals);
    peak_vsep_mean  = mean(v_sep_vals);
    d_align_mean    = mean(d_align_vals);
    clearance_var   = std(d_align_vals);
    sym_idx         = symmetry_index_from_alt_steps(v_sep_vals);

    if use_segments && ~isempty(walk_segments) && ~strcmp(step_mode, 'all')
        fog_count = fog_count_within_segments(steps_for_stats, walk_segments, frame_dt, 1.5);
    else
        fog_count = sum(step_times > 1.5);
    end

    % ------------------------------------------------------------------ %
    % 10. Report struct
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
    report.stride_time_cv_pct         = sprintf('%.2f', stride_time_cv);
    report.peak_vapp_mean_mps         = sprintf('%.3f', peak_vapp_mean);
    report.peak_vsep_mean_mps         = sprintf('%.3f', peak_vsep_mean);
    report.symmetry_index             = sprintf('%.3f', sym_idx);
    report.d_align_mean_cm            = sprintf('%.2f', d_align_mean);
    report.clearance_variability_cm   = sprintf('%.2f', clearance_var);
    report.fog_episode_count          = fog_count;
    report.num_walking_segments       = length(walk_segments);
    report.total_duration_s           = sprintf('%.2f', total_duration);
    report.walking_duration_s         = sprintf('%.2f', walking_duration);
    report.use_segments               = use_segments;
    report.segments_mode              = segments_mode;
    report.segment_pad_s              = sprintf('%.2f', segment_pad_s);
    report.walk_thr_on                = sprintf('%.3f', thr_on);
    report.walk_thr_off               = sprintf('%.3f', thr_off);
    report.min_step_height_mps        = sprintf('%.2f', min_step_height_mps);
    report.step_height_thr_used       = sprintf('%.3f', height_thr_used);
    report.step_height_prc            = height_prc;
    report.step_prom_used             = sprintf('%.3f', prom_used);

    if ~isempty(zoom_time_range)
        report.auto_zoom_start_s = sprintf('%.2f', zoom_time_range(1));
        report.auto_zoom_end_s   = sprintf('%.2f', zoom_time_range(2));
    end

    if ~isempty(p.Results.gt_steps) && p.Results.gt_steps > 0
        err = total_steps_used - p.Results.gt_steps;
        report.gt_steps             = p.Results.gt_steps;
        report.step_count_error     = err;
        report.step_count_error_pct = sprintf('%.2f', (100.0 * err / p.Results.gt_steps));
    end

    % ------------------------------------------------------------------ %
    % 11. Save outputs
    % ------------------------------------------------------------------ %
    fprintf('10. Saving results...\n');
    save_gait_data_to_csv_shoe(fullfile(recording_folder, 'Gait_Analysis_Results_SHOE.csv'), report, step_rows);

    if save_sep_plots
        save_separate_plots_shoe(recording_folder, rt, vt, toe, r_axis, v_axis, ...
            frame_dt, walk_segments, steps_for_plot_all, steps_for_plot_used, ...
            min_step_height_mps, report, zoom_time_range, ...
            rt_vmin_prc, vt_vmin_prc, vmax_prc, dpi_png, v_plot_lim);
    end

    fprintf('\n=== ANALYSIS COMPLETE ===\n');
    fprintf('Total steps: %d\n', total_steps_used);
    fprintf('Cadence: %s spm\n', report.cadence_spm);
    fprintf('Swing velocity: %s m/s\n', report.peak_vsep_mean_mps);
    if ~isempty(zoom_time_range)
        fprintf('Auto-zoom window: [%.2f, %.2f] s\n', zoom_time_range(1), zoom_time_range(2));
    end

    if show
        fprintf('\nReport fields:\n');
        fn = fieldnames(report);
        for i = 1:length(fn)
            val = report.(fn{i});
            if islogical(val),     val_str = char(string(val));
            elseif isnumeric(val), val_str = sprintf('%g', val);
            else,                  val_str = char(val);
            end
            fprintf('  %s: %s\n', fn{i}, val_str);
        end
    end
end


% =========================================================================
%  PUBLICATION-QUALITY PLOT SAVING  —  SHOE-MOUNTED
% =========================================================================
function save_separate_plots_shoe(out_folder, rt, vt, toe, r_axis, v_axis, ...
        frame_dt, walk_segments, peaks_all, peaks_used, min_step_mps, ...
        report, zoom_time_range, rt_vmin_prc, vt_vmin_prc, vmax_prc, dpi_png, v_plot_lim)

    n_frames = size(rt, 2);
    t_axis   = (0 : n_frames-1) * frame_dt;

    % Convert maps to dB
    rt_dB = 20 * log10(abs(rt) + eps);
    vt_dB = 20 * log10(abs(vt) + eps);

    % ---- 1. RT map  (wide landscape: matches original style) ----------
    fh = pub_fig_shoe(12.0, 4.2);
    ax = axes(fh, 'Units', 'normalized', 'Position', [0.07 0.13 0.84 0.78]);
    plot_rt_map_shoe(ax, rt_dB, r_axis, t_axis, rt_vmin_prc, vmax_prc);
    pub_export_shoe(fh, fullfile(out_folder, 'RT_Range_Time'), dpi_png);
    close(fh);

    % ---- 2. VT map  (wide landscape) ---------------------------------
    fh = pub_fig_shoe(12.0, 4.2);
    ax = axes(fh, 'Units', 'normalized', 'Position', [0.07 0.13 0.84 0.78]);
    plot_vt_map_shoe(ax, vt_dB, v_axis, t_axis, vt_vmin_prc, vmax_prc, v_plot_lim);
    pub_export_shoe(fh, fullfile(out_folder, 'VT_Velocity_Time'), dpi_png);
    close(fh);

    % ---- 3. Toe envelope + segments + peaks --------------------------
    fh = pub_fig_shoe(8.5, 3.8);
    set(fh, 'Renderer', 'painters');
    ax = axes(fh, 'Units', 'normalized', 'Position', [0.09 0.14 0.88 0.78]);
    plot_toe_envelope_shoe(ax, toe, frame_dt, walk_segments, ...
        peaks_all, peaks_used, min_step_mps, ...
        'Toe Envelope + Peaks + Segments');
    pub_export_shoe(fh, fullfile(out_folder, 'ToeEnvelope_Peaks_Segments'), dpi_png);
    close(fh);

    % ---- 4. Zoomed step window ---------------------------------------
    if ~isempty(zoom_time_range)
        fh = pub_fig_shoe(5.5, 3.4);
        set(fh, 'Renderer', 'painters');
        ax = axes(fh, 'Units', 'normalized', 'Position', [0.13 0.15 0.83 0.76]);
        plot_zoom_window_shoe(ax, toe, frame_dt, peaks_used, min_step_mps, zoom_time_range);
        pub_export_shoe(fh, fullfile(out_folder, 'Zoomed_Steps'), dpi_png);
        close(fh);
    end

    % ---- 5. Summary text panel ---------------------------------------
    fh = pub_fig_shoe(5.5, 5.0);
    set(fh, 'Renderer', 'painters');
    ax = axes(fh, 'Units', 'normalized', 'Position', [0 0 1 1]);
    plot_summary_panel_shoe(ax, report);
    pub_export_shoe(fh, fullfile(out_folder, 'Summary_Table'), dpi_png);
    close(fh);

    fprintf('   Figures saved to: %s\n', out_folder);
end


% =========================================================================
%  FIGURE CREATION HELPER
% =========================================================================
function fh = pub_fig_shoe(width_in, height_in)
% PUB_FIG_SHOE  Create a correctly sized, white-background publication figure.
    fh = figure( ...
        'Units',         'inches', ...
        'Position',      [1 1 width_in height_in], ...
        'PaperUnits',    'inches', ...
        'PaperSize',     [width_in height_in], ...
        'PaperPosition', [0 0 width_in height_in], ...
        'Color',         'white', ...
        'Renderer',      'opengl', ...
        'Visible',       'off');
    set(fh, 'DefaultAxesFontName',      'Helvetica');
    set(fh, 'DefaultTextFontName',      'Helvetica');
    set(fh, 'DefaultAxesFontSize',      12);
    set(fh, 'DefaultAxesLabelFontSizeMultiplier', 1.08);
    set(fh, 'DefaultAxesTitleFontSizeMultiplier', 1.15);
end


% =========================================================================
%  EXPORT HELPER
% =========================================================================
function pub_export_shoe(fh, filepath_no_ext, dpi)
    if nargin < 3, dpi = 600; end

    png_path = [filepath_no_ext '.png'];
    exportgraphics(fh, png_path, ...
        'Resolution',      dpi, ...
        'BackgroundColor', 'white', ...
        'ContentType',     'image');
    fprintf('   Saved PNG : %s  (%d dpi)\n', png_path, dpi);

    try
        pdf_path = [filepath_no_ext '.pdf'];
        exportgraphics(fh, pdf_path, ...
            'BackgroundColor', 'white', ...
            'ContentType',     'vector');
        fprintf('   Saved PDF : %s\n', pdf_path);
    catch
        % Skip gracefully on older MATLAB versions
    end
end


% =========================================================================
%  RT MAP PLOT  (shoe-mounted: narrow range, burst-pattern signal)
% =========================================================================
function plot_rt_map_shoe(ax, rt_dB, r_axis, t_axis, vmin_prc, vmax_prc)
% PLOT_RT_MAP_SHOE  Publication-quality range-time map for shoe-mounted radar.
%   The shoe RT has a very short range axis (~0-1 m) with vertically bursting
%   energy, so we use less smoothing and tighter colour scaling.

    valid = rt_dB(isfinite(rt_dB));
    clo   = prctile(valid(:), vmin_prc);
    chi   = prctile(valid(:), vmax_prc);

    % Very mild smoothing — preserve the sharp foot-contact burst structure
    rt_plot = imgaussfilt(double(rt_dB), [0.5 0.3]);

    imagesc(ax, t_axis, r_axis, rt_plot);
    axis(ax, 'xy');
    set_clim_shoe(ax, clo, chi);
    ylim(ax, [r_axis(1) r_axis(end)]);
    xlim(ax, [t_axis(1) t_axis(end)]);

    colormap(ax, jet);
    cb = colorbar(ax, 'eastoutside');
    cb.Label.String     = 'dB';
    cb.Label.FontSize   = 12;
    cb.Label.FontWeight = 'bold';
    cb.FontSize         = 11;
    cb.LineWidth        = 0.8;
    cb.TickDirection    = 'out';

    xlabel(ax, 'Time (s)',   'FontSize', 13, 'FontWeight', 'bold');
    ylabel(ax, 'Range (m)',  'FontSize', 13, 'FontWeight', 'bold');
    ax.FontSize   = 12;
    ax.TickLength = [0.012 0.012];
    ax.TickDir    = 'out';
    ax.LineWidth  = 1.0;
    ax.Box        = 'on';
    ax.Layer      = 'top';
    ax.XGrid      = 'off';
    ax.YGrid      = 'off';

    % Y-axis tick spacing: for short range, fine ticks help readability
    if (r_axis(end) - r_axis(1)) < 1.5
        ax.YTick = round(r_axis(1)*10)/10 : 0.1 : round(r_axis(end)*10)/10;
    end
end


% =========================================================================
%  VT MAP PLOT  (shoe-mounted: symmetric burst pattern about 0 m/s)
% =========================================================================
function plot_vt_map_shoe(ax, vt_dB, v_axis, t_axis, vmin_prc, vmax_prc, v_lim)
% PLOT_VT_MAP_SHOE  Publication-quality velocity-time map for shoe-mounted radar.

    if nargin < 7 || isempty(v_lim), v_lim = [-4 4]; end

    valid = vt_dB(isfinite(vt_dB));
    clo   = prctile(valid(:), vmin_prc);
    chi   = prctile(valid(:), vmax_prc);

    % Modest smoothing — the shoe VT has sharp, narrow spikes that should be
    % preserved; over-smoothing merges them into blobs.
    vt_plot = imgaussfilt(double(vt_dB), [0.5 0.3]);

    imagesc(ax, t_axis, v_axis, vt_plot);
    axis(ax, 'xy');
    set_clim_shoe(ax, clo, chi);
    ylim(ax, v_lim);
    xlim(ax, [t_axis(1) t_axis(end)]);

    colormap(ax, jet);
    cb = colorbar(ax, 'eastoutside');
    cb.Label.String     = 'dB';
    cb.Label.FontSize   = 12;
    cb.Label.FontWeight = 'bold';
    cb.FontSize         = 11;
    cb.LineWidth        = 0.8;
    cb.TickDirection    = 'out';

    hold(ax, 'on');
    plot(ax, [t_axis(1) t_axis(end)], [0 0], '--', ...
         'Color', [0.85 0.85 0.85], 'LineWidth', 0.9);
    hold(ax, 'off');

    xlabel(ax, 'Time (s)',                         'FontSize', 13, 'FontWeight', 'bold');
    ylabel(ax, 'Relative radial velocity (m/s)',   'FontSize', 13, 'FontWeight', 'bold');
    ax.FontSize   = 12;
    ax.TickLength = [0.012 0.012];
    ax.TickDir    = 'out';
    ax.LineWidth  = 1.0;
    ax.Box        = 'on';
    ax.Layer      = 'top';
    ax.XGrid      = 'off';
    ax.YGrid      = 'off';
end


% =========================================================================
%  TOE ENVELOPE PLOT  (shoe-mounted)
% =========================================================================
function plot_toe_envelope_shoe(ax, toe, frame_dt, walk_segments, ...
                                 peaks_all, peaks_used, min_step_mps, title_str)
% PLOT_TOE_ENVELOPE_SHOE  Publication-quality toe envelope for shoe-mounted radar.

    t_ax  = (0 : length(toe)-1) * frame_dt;
    y_max = max(toe) * 1.20;

    hold(ax, 'on');

    % --- Walking segment shading
    for k = 1:length(walk_segments)
        t0_seg = (walk_segments{k}(1) - 1) * frame_dt;
        t1_seg = (walk_segments{k}(2) - 1) * frame_dt;
        patch(ax, [t0_seg t1_seg t1_seg t0_seg], [0 0 y_max y_max], ...
              [0.78 0.93 0.78], 'EdgeColor', 'none', 'FaceAlpha', 0.55);
    end

    % --- Threshold
    yline(ax, min_step_mps, ...
          'Color', [0.85 0.10 0.10], ...
          'LineStyle', '--', 'LineWidth', 1.2);
    text(ax, t_ax(end)*0.99, min_step_mps * 1.08, ...
         sprintf('Min step toe = %.2f m/s', min_step_mps), ...
         'HorizontalAlignment', 'right', 'FontSize', 9.5, ...
         'Color', [0.85 0.10 0.10]);

    % --- Toe envelope
    plot(ax, t_ax, toe, 'k-', 'LineWidth', 1.8);

    % --- All peaks (grey)
    if ~isempty(peaks_all)
        t_all = (peaks_all - 1) * frame_dt;
        plot(ax, t_all, toe(peaks_all), 'o', ...
             'MarkerSize', 5, ...
             'MarkerFaceColor', [0.55 0.55 0.55], ...
             'MarkerEdgeColor', 'none');
    end

    % --- Used steps (red)
    if ~isempty(peaks_used)
        t_used = (peaks_used - 1) * frame_dt;
        plot(ax, t_used, toe(peaks_used), 'o', ...
             'MarkerSize', 8, ...
             'MarkerFaceColor', [0.85 0.10 0.10], ...
             'MarkerEdgeColor', 'white', 'LineWidth', 0.8);
    end

    hold(ax, 'off');

    % --- Legend
    leg_h = []; leg_entries = {};
    if ~isempty(peaks_all)
        hold(ax,'on');
        leg_h(end+1)    = plot(ax, NaN, NaN, 'o', 'MarkerSize', 5, ...
                               'MarkerFaceColor', [0.55 0.55 0.55], 'MarkerEdgeColor', 'none');
        leg_entries{end+1} = sprintf('All peaks (n=%d)', length(peaks_all));
        hold(ax,'off');
    end
    hold(ax,'on');
    leg_h(end+1)    = plot(ax, NaN, NaN, 'o', 'MarkerSize', 8, ...
                           'MarkerFaceColor', [0.85 0.10 0.10], ...
                           'MarkerEdgeColor', 'white', 'LineWidth', 0.8);
    leg_entries{end+1} = sprintf('Steps used (n=%d)', length(peaks_used));
    hold(ax,'off');

    if ~isempty(leg_h)
        legend(ax, leg_h, leg_entries, ...
               'Location', 'northeast', 'FontSize', 10, ...
               'Box', 'on', 'EdgeColor', [0.4 0.4 0.4]);
    end

    title(ax, title_str,  'FontSize', 14, 'FontWeight', 'bold');
    xlabel(ax, 'Time (s)',                         'FontSize', 13, 'FontWeight', 'bold');
    ylabel(ax, 'Estimated radial velocity (m/s)',  'FontSize', 13, 'FontWeight', 'bold');
    xlim(ax, [0 t_ax(end)]);
    ylim(ax, [0 y_max]);
    ax.FontSize      = 12;
    ax.TickLength    = [0.010 0.010];
    ax.TickDir       = 'out';
    ax.LineWidth     = 1.0;
    ax.Box           = 'on';
    ax.XGrid         = 'on';
    ax.YGrid         = 'on';
    ax.GridAlpha     = 0.18;
    ax.GridLineStyle = ':';
    ax.Layer         = 'top';
end


% =========================================================================
%  ZOOMED STEP WINDOW PLOT  (shoe-mounted)
% =========================================================================
function plot_zoom_window_shoe(ax, toe, frame_dt, peaks_used, min_step_mps, zoom_range)
% PLOT_ZOOM_WINDOW_SHOE  Zoomed view with step interval annotations.

    t0_fr = max(1,           round(zoom_range(1) / frame_dt) + 1);
    t1_fr = min(length(toe), round(zoom_range(2) / frame_dt) + 1);

    t_zoom   = ((t0_fr-1) : (t1_fr-1)) * frame_dt;
    toe_zoom = toe(t0_fr : t1_fr);
    y_max    = max(toe_zoom) * 1.30;

    hold(ax, 'on');
    plot(ax, t_zoom, toe_zoom, 'k-', 'LineWidth', 2.2);
    yline(ax, min_step_mps, 'r--', 'LineWidth', 1.0);

    mask_z = (peaks_used >= t0_fr) & (peaks_used <= t1_fr);
    pk_z   = peaks_used(mask_z);

    if ~isempty(pk_z)
        t_pk = (pk_z - 1) * frame_dt;
        plot(ax, t_pk, toe(pk_z), 'o', ...
             'MarkerSize', 9, ...
             'MarkerFaceColor', [0.85 0.10 0.10], ...
             'MarkerEdgeColor', 'white', 'LineWidth', 1.0);

        for ii = 1 : length(pk_z) - 1
            dt_step = (pk_z(ii+1) - pk_z(ii)) * frame_dt;
            x_mid   = mean([(pk_z(ii)-1) (pk_z(ii+1)-1)]) * frame_dt;
            y_ann   = max(toe(pk_z(ii)), toe(pk_z(ii+1))) + y_max * 0.07;
            text(ax, x_mid, y_ann, sprintf('%.2f s', dt_step), ...
                 'HorizontalAlignment', 'center', 'FontSize', 9.5, ...
                 'Color', [0.15 0.20 0.60], 'FontWeight', 'bold');
        end
    end
    hold(ax, 'off');

    xlim(ax, zoom_range);
    ylim(ax, [0 y_max]);
    xlabel(ax, 'Time (s)',                         'FontSize', 13, 'FontWeight', 'bold');
    ylabel(ax, 'Estimated radial velocity (m/s)',  'FontSize', 13, 'FontWeight', 'bold');
    title(ax, sprintf('Zoomed Steps  [%.1f – %.1f s]', zoom_range(1), zoom_range(2)), ...
          'FontSize', 13, 'FontWeight', 'bold');
    ax.FontSize      = 12;
    ax.TickLength    = [0.012 0.012];
    ax.TickDir       = 'out';
    ax.LineWidth     = 1.0;
    ax.Box           = 'on';
    ax.XGrid         = 'on';
    ax.YGrid         = 'on';
    ax.GridAlpha     = 0.18;
    ax.GridLineStyle = ':';
    ax.Layer         = 'top';
end


% =========================================================================
%  SUMMARY PANEL  (shoe-mounted)
% =========================================================================
function plot_summary_panel_shoe(ax, report)
% PLOT_SUMMARY_PANEL_SHOE  Clean typeset summary of shoe-mounted gait metrics.

    axis(ax, 'off');
    ax.Color = 'white';

    fields = { ...
        'Step mode',              report.step_mode; ...
        'Total peaks (ALL)',      num2str(report.total_steps_all); ...
        'Peaks in segments',      num2str(report.total_steps_walking); ...
        'Steps used for stats',   num2str(report.total_steps_used_for_stats); ...
        'Cadence',                [report.cadence_spm ' spm']; ...
        'Mean step time',         [report.mean_step_time_s ' s']; ...
        'Step time CV',           [report.step_time_cv_pct ' %']; ...
        'Mean stride time',       [report.mean_stride_time_s ' s']; ...
        'Stride time CV',         [report.stride_time_cv_pct ' %']; ...
        'Swing velocity (v_sep)', [report.peak_vsep_mean_mps ' m/s']; ...
        'Symmetry index',         report.symmetry_index; ...
        'FOG gaps',               num2str(report.fog_episode_count); ...
        '# Walk segments',        num2str(report.num_walking_segments); ...
        'Walking duration',       [report.walking_duration_s ' s']; ...
    };

    n     = size(fields, 1);
    x_lbl = 0.05;
    x_val = 0.62;
    y_top = 0.93;
    dy    = 0.057;

    text(ax, 0.50, 0.985, 'Gait Analysis Summary — Shoe-Mounted Radar', ...
         'Units', 'normalized', 'HorizontalAlignment', 'center', ...
         'FontSize', 13, 'FontWeight', 'bold', 'FontName', 'Helvetica');

    annotation(ax.Parent, 'line', [0.03 0.97], [0.948 0.948], ...
               'Color', [0.3 0.3 0.3], 'LineWidth', 1.0);

    for ii = 1:n
        y_pos = y_top - (ii-1) * dy;
        if mod(ii, 2) == 0
            annotation(ax.Parent, 'rectangle', [0.03 y_pos-dy*0.45 0.94 dy*0.92], ...
                       'FaceColor', [0.95 0.95 0.97], 'EdgeColor', 'none', 'FaceAlpha', 0.8);
        end
        text(ax, x_lbl, y_pos, fields{ii,1}, ...
             'Units', 'normalized', 'FontSize', 11, ...
             'FontName', 'Helvetica', 'Color', [0.15 0.15 0.15]);
        text(ax, x_val, y_pos, fields{ii,2}, ...
             'Units', 'normalized', 'FontSize', 11, ...
             'FontName', 'Helvetica', 'FontWeight', 'bold', 'Color', [0.05 0.20 0.50]);
    end
end


% =========================================================================
%  CLIM HELPER
% =========================================================================
function set_clim_shoe(ax, clo, chi)
    try
        clim(ax, [clo chi]);
    catch
        axes(ax); %#ok<MAXES>
        caxis([clo chi]);
    end
end


% =========================================================================
%  AUTO-ZOOM HELPER
% =========================================================================
function zoom_range = auto_select_zoom_window_shoe(steps_used, toe, frame_dt, ...
        walk_segments, window_s, min_steps, max_steps, regularity_thr)

    zoom_range = [];
    if isempty(steps_used) || length(steps_used) < min_steps
        return;
    end

    win_frames   = round(window_s / frame_dt);
    n_frames     = length(toe);
    step_times_s = steps_used * frame_dt;

    if ~isempty(walk_segments)
        valid_starts = [];
        for k = 1:length(walk_segments)
            s0 = walk_segments{k}(1);
            s1 = walk_segments{k}(2);
            seg_starts = s0 : round(0.1/frame_dt) : max(s0, s1 - win_frames);
            valid_starts = [valid_starts, seg_starts]; %#ok<AGROW>
        end
    else
        valid_starts = 1 : round(0.1/frame_dt) : max(1, n_frames - win_frames);
    end

    if isempty(valid_starts), return; end

    best_score = -Inf;
    best_range = [];

    for fi = valid_starts
        fe = fi + win_frames - 1;
        if fe > n_frames, continue; end

        t0 = (fi - 1) * frame_dt;
        t1 = (fe - 1) * frame_dt;

        mask  = (step_times_s >= t0) & (step_times_s <= t1);
        n_win = sum(mask);

        if n_win < min_steps || n_win > max_steps, continue; end

        t_win = step_times_s(mask);
        if length(t_win) >= 2
            ivs = diff(t_win);
            cv  = std(ivs) / (mean(ivs) + eps);
        else
            cv = Inf;
        end

        if cv > regularity_thr, continue; end

        toe_mean = mean(toe(fi:fe));
        score    = n_win * toe_mean / (cv + 0.05);

        if score > best_score
            best_score = score;
            best_range = [t0, t1];
        end
    end

    zoom_range = best_range;
end