function m = mad(x)
    x = x(:);
    m_val = median(x);
    m = median(abs(x - m_val)) + 1e-6;
end