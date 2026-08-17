function [adc, cfg, meta] = load_recording(folder, expected)
    % LOAD_RECORDING Load radar recording from folder
    % expected = [chirps, rx, samples] e.g., [128, 3, 280] for fixed or [128, 3, 64] for shoe
    
    folder = char(folder);
    
    % Load JSON files
    cfg = load_json(fullfile(folder, 'config.json'));
    meta = load_json(fullfile(folder, 'meta.json'));
    
    % Load radar data - try .mat first, then .npy
    mat_path = fullfile(folder, 'radar.mat');
    npy_path = fullfile(folder, 'radar.npy');
    
    if exist(mat_path, 'file')
        % Load from .mat
        fprintf('Loading from .mat file...\n');
        load(mat_path, 'radar_data');
        adc = radar_data;
    elseif exist(npy_path, 'file')
        % Try Python engine
        fprintf('Loading from .npy file using Python engine...\n');
        try
            adc = py.numpy.load(npy_path);
            adc = double(adc);
        catch ME
            error('Cannot load .npy file. Convert to .mat first or configure Python engine.\nError: %s', ME.message);
        end
    else
        error('Neither radar.mat nor radar.npy found in: %s', folder);
    end
    
    % Convert to complex if needed
    adc = to_complex(adc);
    
    % Reorder to FCRS format
    adc = reorder_to_FCRS(adc, expected);
    
    fprintf('Loaded data shape: %s\n', mat2str(size(adc)));
end