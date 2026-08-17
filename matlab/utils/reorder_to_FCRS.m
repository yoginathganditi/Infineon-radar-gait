function x = reorder_to_FCRS(x, expected)
    % expected = [chirps, rx, samples]
    chirps = expected(1);
    rx = expected(2);
    samples = expected(3);
    
    shp = size(x);
    
    % Find dimensions
    iC = find(shp == chirps, 1);
    iR = find(shp == rx, 1);
    iS = find(shp == samples, 1);
    
    if isempty(iC) || isempty(iR) || isempty(iS)
        error('Cannot find expected dims [%d, %d, %d] in shape %s', chirps, rx, samples, mat2str(shp));
    end
    
    % Find frame dimension (the remaining one)
    dims = 1:ndims(x);
    rest = setdiff(dims, [iC, iR, iS]);
    if length(rest) ~= 1
        error('Expected 1 frame axis, got %d', length(rest));
    end
    iF = rest(1);
    
    % Permute to (F, C, R, S)
    x = permute(x, [iF, iC, iR, iS]);
end