function mask = robust_mask_db(power_2d, k_mad)
    % ROBUST_MASK_DB Create robust mask using MAD threshold
    % Inputs:
    %   power_2d: 2D power map
    %   k_mad: MAD multiplier (default 6.0)
    % Output:
    %   mask: binary mask
    
    if nargin < 2, k_mad = 6.0; end
    
    db = 10 * log10(power_2d + 1e-12);
    med = median(db(:));
    mm = median(abs(db(:) - med)) + 1e-6;
    mask = db > (med + k_mad * mm);
end