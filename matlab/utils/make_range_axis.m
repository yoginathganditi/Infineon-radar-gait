function r_axis = make_range_axis(cfg, nfft_r)
    % MAKE_RANGE_AXIS Create range axis for RT/RD plots
    % Inputs:
    %   cfg: configuration structure
    %   nfft_r: FFT size for range
    % Output:
    %   r_axis: range values in meters
    
    C = 299792458.0;  % Speed of light
    fb = (0:(nfft_r/2-1)) * (cfg.fs / nfft_r);
    r_axis = C * fb / (2.0 * cfg.slope);
end