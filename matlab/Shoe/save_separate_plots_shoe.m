function save_separate_plots_shoe(out_folder, rt, vt, toe, r_axis, v_axis, ...
    frame_dt, walk_segments, steps_all, steps_used, min_step_height_mps, ...
    report_rows, r_gate, v_plot_lim, zoom_time_range, ...
    rt_vmin_percentile, vt_vmin_percentile, vmax_percentile, ...
    smooth_sigma_y, smooth_sigma_x, rt_interpolation, vt_interpolation)
    % SAVE_SEPARATE_PLOTS_SHOE Save RT, VT, and toe plots for shoe-mounted
    
    if nargin < 13, r_gate = [0.10, 1.20]; end
    if nargin < 14, v_plot_lim = [-3.8, 3.8]; end
    if nargin < 15, zoom_time_range = []; end
    if nargin < 16, rt_vmin_percentile = 35.0; end
    if nargin < 17, vt_vmin_percentile = 8.0; end
    if nargin < 18, vmax_percentile = 99.7; end
    if nargin < 19, smooth_sigma_y = 0.3; end
    if nargin < 20, smooth_sigma_x = 0.3; end
    if nargin < 21, rt_interpolation = 'bilinear'; end
    if nargin < 22, vt_interpolation = 'none'; end
    
    out_folder = char(out_folder);
    if ~exist(out_folder, 'dir')
        mkdir(out_folder);
    end
    
    t = (0:(size(rt, 1)-1)) * frame_dt;
    
    % Font sizes (increased for better visibility)
    LABEL_FONT = 42;
    TICK_FONT = 32;
    TITLE_FONT = 36;
    CBAR_FONT = 36;
    LEGEND_FONT = 26;
    SUMMARY_FONT = 22;
    
    % RT Plot (with smoothing if specified)
    fprintf('Saving RT plot...\n');
    if smooth_sigma_y > 0 || smooth_sigma_x > 0
        rt_smooth = imgaussfilt(rt, [smooth_sigma_y, smooth_sigma_x]);
    else
        rt_smooth = rt;
    end
    
    db_rt = db_from_power(rt_smooth);
    [vmin_rt, vmax_rt] = robust_jet_limits(db_rt, rt_vmin_percentile, vmax_percentile, 20.0);
    
    % Calculate actual range extent
    r_idx_gate = range_gate_indices(r_axis, r_gate(1), r_gate(2));
    if ~isempty(r_idx_gate)
        r_min_actual = r_axis(r_idx_gate(1));
        r_max_actual = r_axis(r_idx_gate(end));
    else
        r_min_actual = r_gate(1);
        r_max_actual = r_gate(2);
    end
    
    fig = figure('Position', [100, 100, 2400, 1000], 'Color', 'white');
    imagesc(t, r_axis, db_rt.');
    colormap('jet');
    caxis([vmin_rt, vmax_rt]);
    xlabel('Time (s)', 'FontSize', LABEL_FONT, 'FontWeight', 'bold');
    ylabel('Range (m)', 'FontSize', LABEL_FONT, 'FontWeight', 'bold');
    set(gca, 'YDir', 'normal');
    set(gca, 'FontSize', TICK_FONT, 'FontWeight', 'bold', 'LineWidth', 2.0);
    ylim([r_min_actual, r_max_actual]);
    c = colorbar;
    c.Label.String = 'dB';
    c.Label.FontSize = CBAR_FONT;
    c.Label.FontWeight = 'bold';
    c.FontSize = TICK_FONT;
    set(c, 'FontWeight', 'bold');
    
    fig.PaperPositionMode = 'auto';
    fig.PaperUnits = 'inches';
    fig.PaperSize = [24, 10];
    fig.PaperPosition = [0, 0, 24, 10];
    png_path = fullfile(out_folder, 'RT_Range_Time.png');
    print(fig, png_path, '-dpng', '-r1200');
    try
        pdf_path = fullfile(out_folder, 'RT_Range_Time.pdf');
        print(fig, pdf_path, '-dpdf');
    catch
    end
    try
        if isvalid(fig), close(fig); end
    catch
    end
    
    % VT Plot (no smoothing, crisp Doppler)
    fprintf('Saving VT plot...\n');
    db_vt = db_from_power(vt);
    [vmin_vt, vmax_vt] = robust_jet_limits(db_vt, vt_vmin_percentile, vmax_percentile, 20.0);
    
    fig = figure('Position', [100, 100, 2400, 1000], 'Color', 'white');
    imagesc(t, v_axis, db_vt);
    colormap('jet');
    caxis([vmin_vt, vmax_vt]);
    xlabel('Time (s)', 'FontSize', LABEL_FONT, 'FontWeight', 'bold');
    ylabel('Relative radial velocity (m/s)', 'FontSize', LABEL_FONT, 'FontWeight', 'bold');
    set(gca, 'YDir', 'normal');
    set(gca, 'FontSize', TICK_FONT, 'FontWeight', 'bold', 'LineWidth', 2.0);
    ylim(v_plot_lim);
    c = colorbar;
    c.Label.String = 'dB';
    c.Label.FontSize = CBAR_FONT;
    c.Label.FontWeight = 'bold';
    c.FontSize = TICK_FONT;
    set(c, 'FontWeight', 'bold');
    
    fig.PaperPositionMode = 'auto';
    fig.PaperUnits = 'inches';
    fig.PaperSize = [24, 10];
    fig.PaperPosition = [0, 0, 24, 10];
    png_path = fullfile(out_folder, 'VT_Velocity_Time.png');
    print(fig, png_path, '-dpng', '-r1200');
    try
        pdf_path = fullfile(out_folder, 'VT_Velocity_Time.pdf');
        print(fig, pdf_path, '-dpdf');
    catch
    end
    try
        if isvalid(fig), close(fig); end
    catch
    end
    
    % Toe Plot
    fprintf('Saving toe envelope plot...\n');
    fig = figure('Position', [100, 100, 2400, 1000], 'Color', 'white');
    plot(t, toe, 'LineWidth', 3.0, 'Color', 'black', 'DisplayName', 'Toe Envelope');
    hold on;
    plot([t(1), t(end)], [min_step_height_mps, min_step_height_mps], '--', ...
        'LineWidth', 2.2, 'Color', 'red', ...
        'DisplayName', sprintf('Min step height = %.2f m/s', min_step_height_mps));
    
    if ~isempty(steps_all)
        h1 = scatter(steps_all * frame_dt, toe(steps_all), 60, [0.5, 0.5, 0.5], 'filled');
        set(h1, 'DisplayName', sprintf('All peaks (n=%d)', length(steps_all)));
        try
            set(h1, 'MarkerFaceAlpha', 0.45);
        catch
        end
    end
    if ~isempty(steps_used)
        h2 = scatter(steps_used * frame_dt, toe(steps_used), 80, [1, 0, 0], 'filled');
        set(h2, 'DisplayName', sprintf('Steps used (n=%d)', length(steps_used)));
    end
    
    % Draw walking segments (with HandleVisibility off to exclude from legend)
    y_lim = ylim;
    for i = 1:length(walk_segments)
        seg = walk_segments{i};
        x1 = (seg(1) - 1) * frame_dt;
        x2 = (seg(2) - 1) * frame_dt;
        fill([x1, x2, x2, x1], [y_lim(1), y_lim(1), y_lim(2), y_lim(2)], ...
            'green', 'FaceAlpha', 0.12, 'EdgeColor', 'none', 'HandleVisibility', 'off');
    end
    
    title('Toe Envelope + Peaks + Segments', 'FontSize', TITLE_FONT, 'FontWeight', 'bold');
    xlabel('Time (s)', 'FontSize', LABEL_FONT, 'FontWeight', 'bold');
    ylabel('Relative radial velocity (m/s)', 'FontSize', LABEL_FONT, 'FontWeight', 'bold');
    set(gca, 'FontSize', TICK_FONT, 'FontWeight', 'bold', 'LineWidth', 2.0);
    grid on;
    grid minor;
    
    % Create legend in top-right corner, positioned to avoid waveform
    leg = legend('Location', 'northeast', 'FontSize', LEGEND_FONT, 'Box', 'on', 'AutoUpdate', 'off');
    % Position: [left, bottom, width, height] in normalized units
    % Positioned at top-right corner, compact size
    set(leg, 'Position', [0.82, 0.92, 0.16, 0.08]);
    
    fig.PaperPositionMode = 'auto';
    fig.PaperUnits = 'inches';
    fig.PaperSize = [24, 10];
    fig.PaperPosition = [0, 0, 24, 10];
    png_path = fullfile(out_folder, 'ToeEnvelope_Peaks_Segments.png');
    print(fig, png_path, '-dpng', '-r1200');
    try
        pdf_path = fullfile(out_folder, 'ToeEnvelope_Peaks_Segments.pdf');
        print(fig, pdf_path, '-dpdf');
    catch
    end
    try
        if isvalid(fig), close(fig); end
    catch
    end
    
    % Summary table (simpler text-based version)
    fprintf('Saving summary table...\n');
    fig = figure('Position', [100, 100, 2400, 900], 'Color', 'white');
    ax = axes('Position', [0.03, 0.05, 0.94, 0.90]);
    axis off;
    
    % Ensure report_rows is in correct format
    if iscell(report_rows) && ~isempty(report_rows)
        if iscell(report_rows{1})
            % Already correct: {{'param', 'val'}, {'param', 'val'}, ...}
            table_data = report_rows;
        else
            % Need to convert
            table_data = {};
            for i = 1:length(report_rows)
                if iscell(report_rows{i}) && length(report_rows{i}) >= 2
                    table_data{end+1} = {char(report_rows{i}{1}), char(report_rows{i}{2})};
                end
            end
        end
    else
        error('report_rows format not recognized');
    end
    
    % Display as text
    y_start = 0.95;
    y_step = 0.08;
    y_pos = y_start;
    
    for i = 1:length(table_data)
        param = char(table_data{i}{1});
        val = char(table_data{i}{2});
        text(0.05, y_pos, sprintf('%s: %s', param, val), ...
            'FontSize', SUMMARY_FONT, 'FontWeight', 'bold', ...
            'HorizontalAlignment', 'left', 'Units', 'normalized', ...
            'FontName', 'Times New Roman');
        y_pos = y_pos - y_step;
    end
    
    fig.PaperPositionMode = 'auto';
    fig.PaperUnits = 'inches';
    fig.PaperSize = [24, 9];
    fig.PaperPosition = [0, 0, 24, 9];
    png_path = fullfile(out_folder, 'Summary_Table.png');
    print(fig, png_path, '-dpng', '-r1200');
    try
        pdf_path = fullfile(out_folder, 'Summary_Table.pdf');
        print(fig, pdf_path, '-dpdf');
    catch
    end
    try
        if isvalid(fig), close(fig); end
    catch
    end
end