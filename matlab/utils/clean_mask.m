function m = clean_mask(mask, dil, ero)
    % CLEAN_MASK Clean binary mask with dilation and erosion
    % Inputs:
    %   mask: binary mask
    %   dil: number of dilations
    %   ero: number of erosions
    % Output:
    %   m: cleaned mask
    
    if nargin < 2, dil = 2; end
    if nargin < 3, ero = 2; end
    
    m = mask;
    se = strel('disk', 1);
    
    for i = 1:dil
        m = imdilate(m, se);
    end
    
    for i = 1:ero
        m = imerode(m, se);
    end
end