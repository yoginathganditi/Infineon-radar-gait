function save_gait_data_to_csv(output_path, report, step_data)
    % SAVE_GAIT_DATA_TO_CSV Save gait analysis results to CSV
    % Inputs:
    %   output_path: full path to CSV file
    %   report: structure with global summary
    %   step_data: cell array of step data structures
    
    output_path = char(output_path);
    fid = fopen(output_path, 'w');
    
    if fid == -1
        error('Cannot open file for writing: %s', output_path);
    end
    
    % Header
    fprintf(fid, '=== GLOBAL GAIT SUMMARY (FIXED) ===\n\n');
    fprintf(fid, 'Parameter,Value\n');
    
    % Report fields
    fn = fieldnames(report);
    for i = 1:length(fn)
        val = report.(fn{i});
        
        % Handle different data types
        if islogical(val)
            if val
                val_str = 'true';
            else
                val_str = 'false';
            end
        elseif isnumeric(val)
            if isinteger(val) || mod(val, 1) == 0
                val_str = sprintf('%d', val);
            else
                val_str = sprintf('%g', val);
            end
        elseif ischar(val) || isstring(val)
            val_str = char(val);
        else
            val_str = 'N/A';
        end
        
        fprintf(fid, '%s,%s\n', fn{i}, val_str);
    end
    
    fprintf(fid, '\n=== DETAILED PER-STEP DATA (STEPS USED FOR STATS) ===\n\n');
    fprintf(fid, 'Step_ID,Time_s,Toe_Velocity_m_s,Torso_Velocity_m_s,Step_Time_s,Step_Length_cm,Stride_Time_s,Stride_Length_cm\n');
    
    % Step data
    for i = 1:length(step_data)
        row = step_data{i};
        fprintf(fid, '%d,%.4f,%.4f,%.4f,%.4f,%.2f', ...
            row.step_id, row.time_s, row.toe_velocity_m_s, row.torso_velocity_m_s, ...
            row.step_time_s, row.step_length_cm);
        if row.stride_time_s > 0
            fprintf(fid, ',%.4f,%.2f\n', row.stride_time_s, row.stride_length_cm);
        else
            fprintf(fid, ',\n');
        end
    end
    
    fclose(fid);
    fprintf('✓ CSV saved: %s\n', output_path);
end