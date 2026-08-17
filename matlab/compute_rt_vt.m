function [rt, vt, rd, r_axis, v_axis] = compute_rt_vt()
    % COMPUTE_RT_VT Compute RT and VT maps for a single recording
    
    RECORDING_FOLDER = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\20260203_224805_walk_any_speed';
    
    % FIXED: Changed to match your data shape [128, 3, 64]
    EXPECTED_SHAPE = [128, 3, 64];  % [chirps, rx, samples] for shoe-mounted radar
    
    NFFT_R = 1024;
    NFFT_D = 256;
    
    % FIXED: Changed range gate for shoe-mounted radar
    R_GATE = [0.10, 1.20];
    
    radar_pipeline_path = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\radar_pipeline';
    addpath(genpath(radar_pipeline_path));
    
    fprintf('\n=== Loading Recording ===\n');
    fprintf('Folder: %s\n', RECORDING_FOLDER);
    fprintf('Expected shape: %s\n', mat2str(EXPECTED_SHAPE));
    
    try
        [adc, cfg_json, meta] = load_recording(RECORDING_FOLDER, EXPECTED_SHAPE);
        cfg = derive_cfg_params(cfg_json);
        fprintf('✓ Data loaded successfully\n');
        fprintf('  Shape: %s\n', mat2str(size(adc)));
    catch ME
        error('Failed to load data: %s', ME.message);
    end
    
    fprintf('\n=== Computing RT Map ===\n');
    [rd, rt] = compute_rd_rt(adc, cfg, NFFT_R, NFFT_D);
    fprintf('✓ RT computed\n');
    fprintf('  RT shape: %s\n', mat2str(size(rt)));
    
    fprintf('\n=== Computing VT Map ===\n');
    r_axis = make_range_axis(cfg, NFFT_R);
    v_axis = make_velocity_axis(cfg, NFFT_D);
    r_idx = range_gate_indices(r_axis, R_GATE(1), R_GATE(2));
    vt = vt_from_rd_static(rd, r_idx, 'sum');
    fprintf('✓ VT computed\n');
    fprintf('  VT shape: %s\n', mat2str(size(vt)));
    
    fprintf('\n=== Displaying Results ===\n');
    frame_dt = cfg.frame_T;
    num_frames = size(rt, 1);
    time_axis = (0:num_frames-1) * frame_dt;
    
    figure('Name', 'Range-Time (RT) Map', 'Position', [100, 100, 1200, 600]);
    imagesc(time_axis, r_axis, rt');
    xlabel('Time (s)');
    ylabel('Range (m)');
    title('Range-Time Map');
    colorbar;
    colormap('hot');
    axis xy;
    
    figure('Name', 'Velocity-Time (VT) Map', 'Position', [100, 700, 1200, 600]);
    imagesc(time_axis, v_axis, vt');
    xlabel('Time (s)');
    ylabel('Velocity (m/s)');
    title('Velocity-Time Map');
    colorbar;
    colormap('hot');
    axis xy;
    
    fprintf('\n=== Saving Results ===\n');
    save_path = fullfile(RECORDING_FOLDER, 'rt_vt_results.mat');
    save(save_path, 'rt', 'vt', 'rd', 'r_axis', 'v_axis', 'time_axis', 'cfg');
    fprintf('✓ Results saved to: %s\n', save_path);
    
    fprintf('\n=== Complete ===\n');
end