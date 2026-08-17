function x = to_complex(arr)
    if ~isreal(arr)
        x = complex(single(real(arr)), single(imag(arr)));
    elseif ndims(arr) >= 4 && size(arr, 4) == 2
        x = complex(single(arr(:, :, :, 1)), single(arr(:, :, :, 2)));
    else
        x = complex(single(arr), zeros(size(arr), 'single'));
    end
end