% Test script to verify data loading works
% Make sure all utility functions are in C:\radar_gait_matlab\utils\

% Add the utils folder to MATLAB path
addpath(genpath('C:\radar_gait_matlab'));

% Define folder paths
empty_folder = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\BGT60TR13C_empty20251226-054201\RadarIfxAvian_00';

% Fixed recording - Mani Regular
% IMPORTANT: This path should point to the folder that contains radar.mat, config.json, meta.json
walk_folder = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Mani P1\Regular';

fprintf('=== Testing Data Loading ===\n\n');

% Test 1: Load empty room data
fprintf('Test 1: Loading empty room data...\n');
try
    [bg_adc, ~, ~] = load_recording(empty_folder, [128, 3, 280]);
    fprintf('  ✓ SUCCESS: Empty room loaded\n');
    fprintf('    Shape: %s\n', mat2str(size(bg_adc)));
    fprintf('    Data type: %s\n', class(bg_adc));
    fprintf('    Is complex: %d\n', ~isreal(bg_adc));
catch ME
    fprintf('  ✗ FAILED: %s\n', ME.message);
    fprintf('    Check if radar.mat exists in: %s\n', empty_folder);
    return;  % Stop if this fails
end

fprintf('\n');

% Test 2: Load walking data
fprintf('Test 2: Loading walking data...\n');
try
    [wk_adc, cfg_json, meta] = load_recording(walk_folder, [128, 3, 280]);
    fprintf('  ✓ SUCCESS: Walking data loaded\n');
    fprintf('    Shape: %s\n', mat2str(size(wk_adc)));
    fprintf('    Data type: %s\n', class(wk_adc));
    fprintf('    Is complex: %d\n', ~isreal(wk_adc));
catch ME
    fprintf('  ✗ FAILED: %s\n', ME.message);
    fprintf('    Check if radar.mat exists in: %s\n', walk_folder);
    fprintf('    Or check if the path is correct\n');
    return;  % Stop if this fails
end

fprintf('\n');

% Test 3: Derive config parameters
fprintf('Test 3: Deriving config parameters...\n');
try
    cfg = derive_cfg_params(cfg_json);
    fprintf('  ✓ SUCCESS: Config derived\n');
    fprintf('    Sample rate (fs): %.0f Hz\n', cfg.fs);
    fprintf('    Number of chirps: %d\n', cfg.num_chirps);
    fprintf('    Number of samples: %d\n', cfg.num_samples);
    fprintf('    Number of RX antennas: %d\n', cfg.num_rx);
    fprintf('    Frame time: %.4f s\n', cfg.frame_T);
catch ME
    fprintf('  ✗ FAILED: %s\n', ME.message);
    fprintf('    Check if config.json was loaded correctly\n');
    return;
end

fprintf('\n');

% Test 4: Check data dimensions
fprintf('Test 4: Verifying data dimensions...\n');
[F_bg, C_bg, R_bg, S_bg] = size(bg_adc);
[F_wk, C_wk, R_wk, S_wk] = size(wk_adc);

fprintf('  Empty room: [Frames=%d, Chirps=%d, RX=%d, Samples=%d]\n', F_bg, C_bg, R_bg, S_bg);
fprintf('  Walking:   [Frames=%d, Chirps=%d, RX=%d, Samples=%d]\n', F_wk, C_wk, R_wk, S_wk);

if C_bg == 128 && R_bg == 3 && S_bg == 280
    fprintf('  ✓ Empty room dimensions correct\n');
else
    fprintf('  ✗ Empty room dimensions unexpected\n');
end

if C_wk == 128 && R_wk == 3 && S_wk == 280
    fprintf('  ✓ Walking data dimensions correct\n');
else
    fprintf('  ✗ Walking data dimensions unexpected\n');
end

fprintf('\n=== All Tests Complete ===\n');
fprintf('If all tests passed, you can proceed to next step!\n');