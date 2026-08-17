function [m, cv] = mean_and_cv(x)
    % MEAN_AND_CV Compute mean and coefficient of variation
    % Inputs:
    %   x: array of values
    % Outputs:
    %   m: mean
    %   cv: coefficient of variation (%)
    
    x = x(:);
    if isempty(x)
        m = 0.0;
        cv = 0.0;
        return;
    end
    
    m = mean(x);
    cv = 100.0 * (std(x) / (m + 1e-12));
end