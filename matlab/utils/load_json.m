function data = load_json(json_path)
    fid = fopen(json_path, 'r');
    if fid == -1
        error('Cannot open JSON file: %s', json_path);
    end
    str = fread(fid, '*char')';
    fclose(fid);
    data = jsondecode(str);
end