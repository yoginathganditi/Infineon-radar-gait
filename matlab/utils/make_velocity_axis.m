function v_axis = make_velocity_axis(cfg, nfft_d)
    % MAKE_VELOCITY_AXIS Create velocity axis for VT plots
    % Inputs:
    %   cfg: configuration structure
    %   nfft_d: FFT size for Doppler
    % Output:
    %   v_axis: velocity values in m/s
    
    fd = ((0:(nfft_d-1)) - nfft_d/2) / (nfft_d * cfg.Tr);
    v_axis = (cfg.lam / 2.0) * fd;
end