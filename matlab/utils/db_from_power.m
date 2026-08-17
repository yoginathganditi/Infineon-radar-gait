function db = db_from_power(p)
    db = 10.0 * log10(max(p, 1e-12));
end
