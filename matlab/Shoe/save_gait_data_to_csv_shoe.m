function save_gait_data_to_csv_shoe(output_path, report, step_rows)
    % SAVE_GAIT_DATA_TO_CSV_SHOE Save shoe-mounted gait analysis results to CSV
    
    output_path = char(output_path);
    fid = fopen(output_path, 'w');
    
    if fid == -1
        error('Cannot open file for writing: %s', output_path);
    end
    
    % Header
    fprintf(fid, '=== GLOBAL GAIT SUMMARY (SHOE) ===\n\n');
    fprintf(fid, 'Parameter,Value\n');
    
    % Report fields
    fn = fieldnames(report);
    for i = 1:length(fn)
        val = report.(fn{i});
        
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
    
    fprintf(fid, '\n=== PER-STEP DATA (STEPS USED FOR STATS) ===\n\n');
    fprintf(fid, 'Step,Time(s),Step(s),v_app,v_sep,d_align(cm)\n');
    
    % Step data
    for i = 1:length(step_rows)
        r = step_rows{i};
        fprintf(fid, '%d,%.3f,%.3f,%.3f,%.3f,%.2f\n', ...
            r.step_id, r.time_s, r.step_time_s, r.v_app, r.v_sep, r.d_align_cm);
    end
    
    fclose(fid);
    fprintf('✓ CSV saved: %s\n', output_path);
end