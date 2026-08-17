function sym_idx = symmetry_index_from_alt_steps(values)
    % SYMMETRY_INDEX_FROM_ALT_STEPS Compute symmetry index from alternating steps
    % Inputs:
    %   values: array of values (e.g., v_sep values)
    % Output:
    %   sym_idx: symmetry index (0 = perfect symmetry, higher = more asymmetry)
    
    v = values(:);
    if length(v) < 4
        sym_idx = 0.0;
        return;
    end
    
    odd = v(1:2:end);
    even = v(2:2:end);
    
    m1 = mean(odd);
    m2 = mean(even);
    denom = (m1 + m2) / 2.0 + 1e-12;
    sym_idx = abs(m1 - m2) / denom;
end