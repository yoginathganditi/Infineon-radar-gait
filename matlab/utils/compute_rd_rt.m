function [rd, rt] = compute_rd_rt(adc, cfg, nfft_r, nfft_d)
    % COMPUTE_RD_RT Compute Range-Doppler and Range-Time maps
    % Inputs:
    %   adc: (F, C, R, S) - Frames, Chirps, RX, Samples
    %   cfg: configuration structure
    %   nfft_r: FFT size for range (default 1024)
    %   nfft_d: FFT size for Doppler (default 256)
    % Outputs:
    %   rd: (F, R, V) - Range-Doppler map
    %   rt: (F, R) - Range-Time map
    
    if nargin < 3, nfft_r = 1024; end
    if nargin < 4, nfft_d = 256; end
    
    [F, Cc, Rr, Ss] = size(adc);
    
    % Windows
    win_r = hanning(Ss);
    win_d = blackman(Cc);
    
    % Reshape windows for broadcasting
    win_r_4d = reshape(win_r, [1, 1, 1, length(win_r)]);
    win_d_4d = reshape(win_d, [1, length(win_d), 1, 1]);
    
    % Range FFT along samples dimension (dimension 4)
    adc_windowed = adc .* win_r_4d;
    Xr = fft(adc_windowed, nfft_r, 4);  % FFT along samples dimension
    Xr = Xr(:, :, :, 1:nfft_r/2);  % Take first half
    % Now Xr is (F, C, R, nfft_r/2)
    
    % Remove static clutter (mean across chirps, dimension 2)
    Xr = Xr - mean(Xr, 2);  % Mean along chirp dimension
    % Still (F, C, R, nfft_r/2)
    
    % Doppler FFT along chirp dimension (dimension 2)
    Xr = Xr .* win_d_4d;
    Xd = fftshift(fft(Xr, nfft_d, 2), 2);  % FFT along chirp dimension
    % Now Xd is (F, nfft_d, R, nfft_r/2)
    
    % Power: sum over RX antennas (dimension 3)
    % Xd is (F, nfft_d, R, nfft_r/2), so sum over dim 3 gives (F, nfft_d, 1, nfft_r/2)
    p = sum(abs(Xd).^2, 3);
    
    % Remove singleton dimension (if R=1, we get a singleton dim)
    p = squeeze(p);
    % Now p is (F, nfft_d, nfft_r/2) = (F, V, R)
    
    % Permute to (F, R, V)
    rd = permute(p, [1, 3, 2]);
    
    % Sum over velocity dimension to get RT
    rt = sum(rd, 3);
end