function save_separate_plots_fixed(out_folder, rt, vt, toe, r_axis, v_axis, ...
    frame_dt, walk_segments, steps_all, steps_used, min_step_toe_mps, ...
    report, zoom_time_range, vmin_prc, vmax_prc, min_range_db, dpi_png)
    % SAVE_SEPARATE_PLOTS_FIXED Save RT, VT, and toe plots
    
    if nargin < 13, zoom_time_range = []; end
    if nargin < 14, vmin_prc = 35.0; end
    if nargin < 15, vmax_prc = 99.5; end
    if nargin < 16, min_range_db = 25.0; end
    if nargin < 17, dpi_png = 1200; end
    
    out_folder = char(out_folder);
    if ~exist(out_folder, 'dir')
        mkdir(out_folder);
    end
    
    t = (0:(size(rt, 1)-1)) * frame_dt;
    
    % Font sizes (increased for better visibility)
    AX_LBL_FS = 48;
    TICK_FS = 36;
    CBAR_FS = 42;
    TITLE_FS = 40;
    LEGEND_FS = 28;
    
    % RT Plot
    fprintf('Saving RT plot...\n');
    db_rt = db_from_power(rt);
    [vmin_rt, vmax_rt] = robust_jet_limits(db_rt, vmin_prc, vmax_prc, min_range_db);
    
    fig = figure('Position', [100, 100, 2400, 1350], 'Color', 'white');
    imagesc(t, r_axis, db_rt.');
    colormap('jet');
    caxis([vmin_rt, vmax_rt]);
    xlabel('Time (s)', 'FontSize', AX_LBL_FS, 'FontWeight', 'bold', 'Color', 'black');
    ylabel('Range (m)', 'FontSize', AX_LBL_FS, 'FontWeight', 'bold', 'Color', 'black');
    set(gca, 'YDir', 'normal');
    set(gca, 'FontSize', TICK_FS, 'FontWeight', 'bold', 'LineWidth', 2.5);
    set(gca, 'TickLength', [0.01, 0.01]);
    c = colorbar;
    c.Label.String = 'dB';
    c.Label.FontSize = CBAR_FS;
    c.Label.FontWeight = 'bold';
    c.FontSize = TICK_FS;
    set(c, 'FontWeight', 'bold');
    
    % Fix PDF size
    fig.PaperPositionMode = 'auto';
    fig.PaperUnits = 'inches';
    fig.PaperSize = [24, 13.5];
    fig.PaperPosition = [0, 0, 24, 13.5];
    
    % Save PNG
    png_path = fullfile(out_folder, 'RT_Range_Time.png');
    print(fig, png_path, '-dpng', sprintf('-r%d', dpi_png));
    
    % Save PDF (with error handling)
    try
        pdf_path = fullfile(out_folder, 'RT_Range_Time.pdf');
        print(fig, pdf_path, '-dpdf');
    catch ME
        fprintf('  Warning: Could not save PDF: %s\n', ME.message);
    end
    
    % Close figure safely
    try
        if isvalid(fig)
            close(fig);
        end
    catch
        % Figure already closed or invalid
    end
    
    % VT Plot
    fprintf('Saving VT plot...\n');
    db_vt = db_from_power(vt);
    [vmin_vt, vmax_vt] = robust_jet_limits(db_vt, vmin_prc, vmax_prc, min_range_db);
    
    fig = figure('Position', [100, 100, 2400, 1350], 'Color', 'white');
    imagesc(t, v_axis, db_vt);
    colormap('jet');
    caxis([vmin_vt, vmax_vt]);
    xlabel('Time (s)', 'FontSize', AX_LBL_FS, 'FontWeight', 'bold', 'Color', 'black');
    ylabel('Estimated radial velocity (m/s)', 'FontSize', AX_LBL_FS, 'FontWeight', 'bold', 'Color', 'black');
    set(gca, 'YDir', 'normal');
    set(gca, 'FontSize', TICK_FS, 'FontWeight', 'bold', 'LineWidth', 2.5);
    set(gca, 'TickLength', [0.01, 0.01]);
    c = colorbar;
    c.Label.String = 'dB';
    c.Label.FontSize = CBAR_FS;
    c.Label.FontWeight = 'bold';
    c.FontSize = TICK_FS;
    set(c, 'FontWeight', 'bold');
    
    % Fix PDF size
    fig.PaperPositionMode = 'auto';
    fig.PaperUnits = 'inches';
    fig.PaperSize = [24, 13.5];
    fig.PaperPosition = [0, 0, 24, 13.5];
    
    % Save PNG
    png_path = fullfile(out_folder, 'VT_Velocity_Time.png');
    print(fig, png_path, '-dpng', sprintf('-r%d', dpi_png));
    
    % Save PDF (with error handling)
    try
        pdf_path = fullfile(out_folder, 'VT_Velocity_Time.pdf');
        print(fig, pdf_path, '-dpdf');
    catch ME
        fprintf('  Warning: Could not save PDF: %s\n', ME.message);
    end
    
    % Close figure safely
    try
        if isvalid(fig)
            close(fig);
        end
    catch
        % Figure already closed or invalid
    end
    
    % Toe Plot
    fprintf('Saving toe envelope plot...\n');
    fig = figure('Position', [100, 100, 2400, 1200], 'Color', 'white');
    plot(t, toe, 'LineWidth', 3.0, 'Color', 'black', 'DisplayName', 'Toe Envelope');
    hold on;
    
    % Horizontal line
    plot([t(1), t(end)], [min_step_toe_mps, min_step_toe_mps], '--', ...
        'LineWidth', 2.2, 'Color', 'red', ...
        'DisplayName', sprintf('Min step toe = %.2f m/s', min_step_toe_mps));
    
    % Scatter plots with RGB colors
    if ~isempty(steps_all)
        h1 = scatter(steps_all * frame_dt, toe(steps_all), 50, [0.5, 0.5, 0.5], 'filled');
        set(h1, 'DisplayName', sprintf('All peaks (n=%d)', length(steps_all)));
        try
            set(h1, 'MarkerFaceAlpha', 0.45);
        catch
            % MarkerFaceAlpha not available in older MATLAB versions
        end
    end
    if ~isempty(steps_used)
        h2 = scatter(steps_used * frame_dt, toe(steps_used), 70, [1, 0, 0], 'filled');
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
    
    title('Toe Envelope + Peaks + Segments', 'FontSize', TITLE_FS, 'FontWeight', 'bold', 'Color', 'black');
    xlabel('Time (s)', 'FontSize', AX_LBL_FS, 'FontWeight', 'bold', 'Color', 'black');
    ylabel('Estimated radial velocity (m/s)', 'FontSize', AX_LBL_FS, 'FontWeight', 'bold', 'Color', 'black');
    set(gca, 'FontSize', TICK_FS, 'FontWeight', 'bold', 'LineWidth', 2.5);
    set(gca, 'TickLength', [0.01, 0.01]);
    grid on;
    grid minor;
    
    % Create legend in top-right corner, positioned to avoid waveform
    leg = legend('Location', 'northeast', 'FontSize', LEGEND_FS, 'Box', 'on', 'AutoUpdate', 'off');
    % Position: [left, bottom, width, height] in normalized units
    % Positioned at top-right corner, compact size
    set(leg, 'Position', [0.82, 0.92, 0.16, 0.08]);
    
    % Fix PDF size
    fig.PaperPositionMode = 'auto';
    fig.PaperUnits = 'inches';
    fig.PaperSize = [24, 12];
    fig.PaperPosition = [0, 0, 24, 12];
    
    % Save PNG
    png_path = fullfile(out_folder, 'ToeEnvelope_Peaks_Segments.png');
    print(fig, png_path, '-dpng', sprintf('-r%d', dpi_png));
    
    % Save PDF (with error handling)
    try
        pdf_path = fullfile(out_folder, 'ToeEnvelope_Peaks_Segments.pdf');
        print(fig, pdf_path, '-dpdf');
    catch ME
        fprintf('  Warning: Could not save PDF: %s\n', ME.message);
    end
    
    % Close figure safely
    try
        if isvalid(fig)
            close(fig);
        end
    catch
        % Figure already closed or invalid
    end
    
    fprintf('✓ All plots saved to: %s\n', out_folder);
end