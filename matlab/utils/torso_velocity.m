function torso_v = torso_velocity(torso_r, frame_dt)
    % TORSO_VELOCITY Compute torso velocity from range
    % Inputs:
    %   torso_r: (F,) torso range over time
    %   frame_dt: frame time interval (s)
    % Output:
    %   torso_v: (F,) torso velocity over time
    
    torso_v = gradient(torso_r, frame_dt);
    torso_v = imgaussfilt(torso_v, 1.0, 'FilterSize', 5);
end