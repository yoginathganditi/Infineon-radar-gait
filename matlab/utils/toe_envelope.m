function [toe, mask] = toe_envelope(vt, v_axis)
    % TOE_ENVELOPE Extract toe-off envelope from velocity-time map
    % Inputs:
    %   vt: (V, F) velocity-time map
    %   v_axis: velocity axis values
    % Outputs:
    %   toe: (F,) toe envelope
    %   mask: (V, F) binary mask
    
    % Robust mask
    mask = robust_mask_db(vt, 6.0);
    mask = clean_mask(mask, 2, 2);
    
    vabs = abs(v_axis);
    toe = zeros(1, size(vt, 2), 'single');
    
    for t = 1:size(vt, 2)
        idx = find(mask(:, t));
        if length(idx) >= 5
            toe(t) = prctile(vabs(idx), 98);
        else
            toe(t) = 0.0;
        end
    end
    
    % Smooth
    toe = imgaussfilt(toe, 1.0, 'FilterSize', 5);
end