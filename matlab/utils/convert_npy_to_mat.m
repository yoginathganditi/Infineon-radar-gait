function convert_npy_to_mat(folders)
    % CONVERT_NPY_TO_MAT Convert radar.npy files to radar.mat files
    %
    % Usage:
    %   convert_npy_to_mat()  % Convert all .npy files in base directory
    %   convert_npy_to_mat(folder_path)  % Convert specific folder
    %   convert_npy_to_mat({folder1, folder2, ...})  % Convert multiple folders
    %
    % Example:
    %   convert_npy_to_mat('C:\Users\...\RadarIfxAvian_00')
    
    BASE_DIR = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C';
    
    % Check if Python is available
    try
        pyversion;
        python_available = true;
    catch
        python_available = false;
    end
    
    if ~python_available
        fprintf('\n============================================================\n');
        fprintf('ERROR: Python is not configured in MATLAB\n');
        fprintf('============================================================\n');
        fprintf('Please use the Python script instead:\n');
        fprintf('  1. Open Command Prompt or PowerShell\n');
        fprintf('  2. Navigate to: C:\\radar_gait_matlab\n');
        fprintf('  3. Run: python convert_npy_to_mat.py\n');
        fprintf('\nOr install Python and configure it in MATLAB:\n');
        fprintf('  pyversion ''path\\to\\python.exe''\n');
        fprintf('============================================================\n\n');
        return;
    end
    
    % Handle input arguments
    if nargin == 0
        % Convert all .npy files in base directory
        fprintf('=== Converting all radar.npy files to radar.mat ===\n\n');
        folders_to_convert = find_all_npy_folders(BASE_DIR);
    elseif ischar(folders) || isstring(folders)
        % Single folder
        folders_to_convert = {char(folders)};
    elseif iscell(folders)
        % Multiple folders
        folders_to_convert = folders;
    else
        error('Invalid input. Provide folder path(s) as string or cell array.');
    end
    
    if isempty(folders_to_convert)
        fprintf('No .npy files found to convert.\n');
        return;
    end
    
    fprintf('Found %d folder(s) to process\n\n', length(folders_to_convert));
    
    converted = 0;
    skipped = 0;
    failed = 0;
    
    for i = 1:length(folders_to_convert)
        folder = folders_to_convert{i};
        npy_path = fullfile(folder, 'radar.npy');
        mat_path = fullfile(folder, 'radar.mat');
        
        % Check if .npy exists
        if ~exist(npy_path, 'file')
            fprintf('✗ Skipping: radar.npy not found in %s\n', folder);
            skipped = skipped + 1;
            continue;
        end
        
        % Check if .mat already exists
        if exist(mat_path, 'file')
            fprintf('⊗ Already exists: %s\n', folder);
            skipped = skipped + 1;
            continue;
        end
        
        % Convert using Python
        try
            fprintf('Converting: %s\n', folder);
            data = py.numpy.load(npy_path, pyargs('allow_pickle', false));
            data_mat = double(data);
            save(mat_path, 'data_mat', '-v7.3');
            
            % Rename variable to match expected name
            load(mat_path, 'data_mat');
            radar_data = data_mat;
            save(mat_path, 'radar_data', '-v7.3');
            clear data_mat radar_data;
            
            fprintf('  ✓ Saved: %s\n', mat_path);
            converted = converted + 1;
        catch ME
            fprintf('  ✗ Error: %s\n', ME.message);
            failed = failed + 1;
        end
    end
    
    fprintf('\n=== Conversion Summary ===\n');
    fprintf('Converted: %d\n', converted);
    fprintf('Skipped: %d\n', skipped);
    fprintf('Failed: %d\n', failed);
    fprintf('Total: %d\n\n', length(folders_to_convert));
end

function folders = find_all_npy_folders(base_dir)
    % Find all folders containing radar.npy files
    folders = {};
    
    if ~exist(base_dir, 'dir')
        fprintf('Base directory not found: %s\n', base_dir);
        return;
    end
    
    % Search recursively for radar.npy files
    npy_files = dir(fullfile(base_dir, '**', 'radar.npy'));
    
    for i = 1:length(npy_files)
        folders{end+1} = npy_files(i).folder;
    end
end