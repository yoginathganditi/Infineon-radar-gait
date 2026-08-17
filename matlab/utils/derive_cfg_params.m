function cfg = derive_cfg_params(config_json)
    s = config_json.device_config.fmcw_single_shape;
    fs = double(s.sample_rate_Hz);
    ns = int32(s.num_samples_per_chirp);
    nc = int32(s.num_chirps_per_frame);
    rx = length(s.rx_antennas);
    f_start = double(s.start_frequency_Hz);
    f_end = double(s.end_frequency_Hz);
    Tr = double(s.chirp_repetition_time_s);
    frame_T = double(s.frame_repetition_time_s);
    
    C = 299792458.0;
    B = f_end - f_start;
    f0 = 0.5 * (f_start + f_end);
    lam = C / f0;
    Tc = double(ns) / fs;
    slope = B / Tc;
    
    cfg = struct();
    cfg.fs = fs;
    cfg.num_samples = double(ns);
    cfg.num_chirps = double(nc);
    cfg.num_rx = rx;
    cfg.f_start = f_start;
    cfg.f_end = f_end;
    cfg.f0 = f0;
    cfg.B = B;
    cfg.lam = lam;
    cfg.Tr = Tr;
    cfg.frame_T = frame_T;
    cfg.Tc = Tc;
    cfg.slope = slope;
end