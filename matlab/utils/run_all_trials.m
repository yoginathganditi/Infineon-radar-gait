function run_all_trials()
% RUN_ALL_TRIALS  Batch process all recordings — 8 participants total.
%
%   Original cohort : Mani (P1), Yogi (P2), Srinath (P3), Manohar (P4)
%   New cohort      : Hari (P5), Raj (P6), Vijay (P7), Sudeep (P8)
%
% HOW TO USE
%   Option A — Run ONE subject/pattern/sensor:
%       Set SUBJECT, PATTERN, SENSOR in the CONTROL PANEL and run.
%   Option B — Run ALL subjects for a given pattern/sensor:
%       Set RUN_ALL_SUBJECTS = true, then set PATTERN + SENSOR.
%   Option C — Run EVERYTHING:
%       Set RUN_ALL_SUBJECTS = true, PATTERN = 'all', SENSOR = 'both'.

    addpath(genpath('C:\radar_gait_matlab'));

    % =====================================================================
    % EMPTY ROOM PATH  (shared across ALL fixed-radar trials)
    % =====================================================================
    EMPTY_ROOM_PATH = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Empty_Hall_Riverside\RadarIfxAvian_00';

    % =====================================================================
    % CONTROL PANEL  —  the only section you need to edit day-to-day
    % =====================================================================
    SUBJECT  = 'Manohar';
    PATTERN  = 'slow';       % regular / slow / fast / festination / fog / all
    SENSOR   = 'fixed';     % fixed / shoe / both

    RUN_ALL_SUBJECTS       = false;
    USE_SEGMENTS           = true;
    SEGMENTS_MODE          = 'hysteresis';
    STEP_MODE              = 'hybrid';

    % =====================================================================
    % PER-PATTERN STEP HEIGHT THRESHOLDS
    % =====================================================================
    %
    %  FIXED RADAR  — torso bulk-motion leakage requires higher floor for
    %                  normal walking, but must drop for pathologic patterns
    %                  where swing amplitude is genuinely lower.
    %
    %   regular   : 1.80 m/s  — strong swing peaks, reject torso leakage
    %   slow      : 1.20 m/s  — reduced swing → lower peaks (~1.0–2.0 m/s)
    %   fast      : 1.80 m/s  — same as regular
    %   festination: 0.80 m/s — rapid short steps, amplitude naturally lower
    %   fog       : 0.35 m/s  — shuffle steps produce peaks as low as 0.3 m/s
    %
    %  SHOE RADAR  — near-field relative motion, no torso leakage,
    %               thresholds stay low across all patterns.
    %
    %   regular   : 0.20 m/s
    %   slow      : 0.15 m/s
    %   fast      : 0.20 m/s
    %   festination: 0.12 m/s
    %   fog       : 0.10 m/s  — very small shuffle peaks
    %
    FIXED_THR = struct( ...
        'regular',     1.80, ...
        'slow',        0.80, ...
        'fast',        1.80, ...
        'festination', 0.45, ...
        'fog',         0.35);

    SHOE_THR = struct( ...
        'regular',     0.20, ...
        'slow',        0.15, ...
        'fast',        0.20, ...
        'festination', 0.12, ...
        'fog',         0.10);

    DYNAMIC_GATE_HALFWIDTH_M = 0.8;
    SAVE_SEPARATE_PLOTS      = true;
    SHOW_PLOTS               = false;
    RUN_ALL_TRIALS_IF_LIST   = true;
    TRIAL_INDEX_IF_LIST      = 0;

    % =====================================================================
    % AUTO-ZOOM SETTINGS  (per-pattern overrides below)
    % =====================================================================
    ZOOM_WINDOW_S       = 2.0;
    ZOOM_MIN_STEPS      = 3;
    ZOOM_MAX_STEPS      = 6;
    ZOOM_REGULARITY_THR = 0.35;
    ZOOM_TIME_RANGE     = [];

    % =====================================================================
    % MASTER LISTS
    % =====================================================================
    ALL_SUBJECTS = {'Mani','Yogi','Srinath','Manohar','Hari','Raj','Vijay','Sudeep'};
    ALL_PATTERNS = {'regular','slow','fast','festination','fog'};

    % =====================================================================
    % DATASET PATHS — FIXED RADAR
    % =====================================================================
    FIXED_DATA = struct();

    % ---- P1: Mani -------------------------------------------------------
    FIXED_DATA.Mani.regular     = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\two_persons20260219-144928\RadarIfxAvian_00';
    FIXED_DATA.Mani.slow        = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Mani P1\Slow';
    FIXED_DATA.Mani.fast        = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\fast_prof20260212-162613\RadarIfxAvian_00';
    FIXED_DATA.Mani.festination = {'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Mani P1\Festination\trial 1', ...
                                   'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Mani P1\Festination\trial 2', ...
                                   'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Mani P1\Festination\trial 3'};
    FIXED_DATA.Mani.fog         = {'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Mani P1\Fog\trial 1', ...
                                   'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Mani P1\Fog\trial 2', ...
                                   'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Mani P1\Fog\trial 3'};

    % ---- P2: Yogi -------------------------------------------------------
    FIXED_DATA.Yogi.regular     = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Yogi P2\Regular';
    FIXED_DATA.Yogi.slow        = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Yogi P2\Slow';
    FIXED_DATA.Yogi.fast        = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Yogi P2\Fast';
    FIXED_DATA.Yogi.festination = {'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Yogi P2\Festination\trial 1', ...
                                   'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Yogi P2\Festination\trial 2', ...
                                   'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Yogi P2\Festination\trial 3'};
    FIXED_DATA.Yogi.fog         = {'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Yogi P2\Fog\trial 1', ...
                                   'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Yogi P2\Fog\trial 2', ...
                                   'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Yogi P2\Fog\trial 3'};

    % ---- P3: Srinath ----------------------------------------------------
    FIXED_DATA.Srinath.regular     = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Srinath P3\Regular';
    FIXED_DATA.Srinath.slow        = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Srinath P3\Slow';
    FIXED_DATA.Srinath.fast        = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Srinath P3\Fast';
    FIXED_DATA.Srinath.festination = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Srinath P3\Festination';
    FIXED_DATA.Srinath.fog         = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Srinath P3\Fog';

    % ---- P4: Manohar ----------------------------------------------------
    FIXED_DATA.Manohar.regular     = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Manohar P4\Regular';
    FIXED_DATA.Manohar.slow        = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Manohar P4\Slow';
    FIXED_DATA.Manohar.fast        = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Manohar P4\Fast';
    FIXED_DATA.Manohar.festination = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Manohar P4\Festination';
    FIXED_DATA.Manohar.fog         = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Manohar P4\Fog';

    % ---- P5: Hari -------------------------------------------------------
    FIXED_DATA.Hari.regular     = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Hari\Fixed\hari_regular20260301-131608\RadarIfxAvian_00';
    FIXED_DATA.Hari.slow        = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Hari\Fixed\hari_slow20260301-131727\RadarIfxAvian_00';
    FIXED_DATA.Hari.fast        = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Hari\Fixed\hari_fast20260301-131832\RadarIfxAvian_00';
    FIXED_DATA.Hari.festination = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Hari\Fixed\hari_festination20260301-132013\RadarIfxAvian_00';
    FIXED_DATA.Hari.fog         = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Hari\Fixed\hari_fog20260301-132138\RadarIfxAvian_00';

    % ---- P6: Raj --------------------------------------------------------
    FIXED_DATA.Raj.regular     = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Raj\Fixed\raj_regular20260301-122426\RadarIfxAvian_00';
    FIXED_DATA.Raj.slow        = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Raj\Fixed\raj_slow20260301-122605\RadarIfxAvian_00';
    FIXED_DATA.Raj.fast        = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Raj\Fixed\raj_fast20260301-122717\RadarIfxAvian_00';
    FIXED_DATA.Raj.festination = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Raj\Fixed\raj_festination20260301-122841\RadarIfxAvian_00';
    FIXED_DATA.Raj.fog         = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Raj\Fixed\raj_fog20260301-123008\RadarIfxAvian_00';

    % ---- P7: Vijay ------------------------------------------------------
    FIXED_DATA.Vijay.regular     = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Vijay\Fixed\vijay_regular20260301-121317\RadarIfxAvian_00';
    FIXED_DATA.Vijay.slow        = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Vijay\Fixed\vijay_slow20260301-121435\RadarIfxAvian_00';
    FIXED_DATA.Vijay.fast        = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Vijay\Fixed\vijay_fast20260301-121540\RadarIfxAvian_00';
    FIXED_DATA.Vijay.festination = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Vijay\Fixed\vijay_festination20260301-121915\RadarIfxAvian_00';
    FIXED_DATA.Vijay.fog         = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Vijay\Fixed\vijay_fog20260301-122102\RadarIfxAvian_00';

    % ---- P8: Sudeep -----------------------------------------------------
    FIXED_DATA.Sudeep.regular     = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Sudeep\Fixed\sudeep_regular20260301-130319\RadarIfxAvian_00';
    FIXED_DATA.Sudeep.slow        = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Sudeep\Fixed\sudeep_slow20260301-130516\RadarIfxAvian_00';
    FIXED_DATA.Sudeep.fast        = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Sudeep\Fixed\sudeep_fast20260301-130636\RadarIfxAvian_00';
    FIXED_DATA.Sudeep.festination = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Sudeep\Fixed\sudeep_festination20260301-130958\RadarIfxAvian_00';
    FIXED_DATA.Sudeep.fog         = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Sudeep\Fixed\sudeep_fog20260301-131304\RadarIfxAvian_00';

    % =====================================================================
    % DATASET PATHS — SHOE-MOUNTED
    % =====================================================================
    SHOE_DATA = struct();

    % ---- P1: Mani -------------------------------------------------------
    SHOE_DATA.Mani.regular     = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\mani_regularshoe20260218-115859\RadarIfxAvian_00';
    SHOE_DATA.Mani.slow        = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\mani_slowshoe20260218-120026\RadarIfxAvian_00';
    SHOE_DATA.Mani.fast        = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\mani_fastshoe120260218-120252\RadarIfxAvian_00';
    SHOE_DATA.Mani.festination = {'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Shoe\Mani P1\Festination\trial 1'};
    SHOE_DATA.Mani.fog         = {'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Shoe\Mani P1\Fog\trial 1'};

    % ---- P2: Yogi -------------------------------------------------------
    SHOE_DATA.Yogi.regular     = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Shoe\Yogi P2\Regular';
    SHOE_DATA.Yogi.slow        = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Shoe\Yogi P2\Slow';
    SHOE_DATA.Yogi.fast        = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Shoe\Yogi P2\Fast';
    SHOE_DATA.Yogi.festination = {'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Shoe\Yogi P2\Festination\trial 1'};
    SHOE_DATA.Yogi.fog         = {'C:\Users\GANDITI YOGINATH\Documents\RadarFusionGUI\BGT60TR13C\yogi_shoe__hor_fog_trail220251230-022110\RadarIfxAvian_00'};

    % ---- P3: Srinath ----------------------------------------------------
    SHOE_DATA.Srinath.regular     = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Shoe\Srinath P3\Regular';
    SHOE_DATA.Srinath.slow        = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Shoe\Srinath P3\Slow';
    SHOE_DATA.Srinath.fast        = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Shoe\Srinath P3\Fast';
    SHOE_DATA.Srinath.festination = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Shoe\Srinath P3\Festination';
    SHOE_DATA.Srinath.fog         = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Shoe\Srinath P3\Fog';

    % ---- P4: Manohar ----------------------------------------------------
    SHOE_DATA.Manohar.regular     = 'C:\Users\GANDITI YOGINATH\Documents\RadarFusionGUI\BGT60TR13C\manohar_shoe_final_regular20260101-013928\RadarIfxAvian_00';
    SHOE_DATA.Manohar.slow        = 'C:\Users\GANDITI YOGINATH\Documents\RadarFusionGUI\BGT60TR13C\manohar_shoe_final_slow20260101-014107\RadarIfxAvian_00';
    SHOE_DATA.Manohar.fast        = 'C:\Users\GANDITI YOGINATH\Documents\RadarFusionGUI\BGT60TR13C\manohar_shoe_final_fast20260101-014241\RadarIfxAvian_00';
    SHOE_DATA.Manohar.festination = 'C:\Users\GANDITI YOGINATH\Documents\RadarFusionGUI\BGT60TR13C\manohar_shoe_final_festination20260101-014409\RadarIfxAvian_00';
    SHOE_DATA.Manohar.fog         = 'C:\Users\GANDITI YOGINATH\Documents\RadarFusionGUI\BGT60TR13C\manohar_shoe_final_fog20260101-014536\RadarIfxAvian_00';

    % ---- P5: Hari -------------------------------------------------------
    SHOE_DATA.Hari.regular     = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Hari\Shoe\hari_shoe_regular20260301-132502\RadarIfxAvian_00';
    SHOE_DATA.Hari.slow        = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Hari\Shoe\hari_shoe_slow20260301-132624\RadarIfxAvian_00';
    SHOE_DATA.Hari.fast        = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Hari\Shoe\hari_shoe_fast20260301-132751\RadarIfxAvian_00';
    SHOE_DATA.Hari.festination = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Hari\Shoe\hari_shoe_festination20260301-133152\RadarIfxAvian_00';
    SHOE_DATA.Hari.fog         = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Hari\Shoe\hari_shoe_fog20260301-133355\RadarIfxAvian_00';

    % ---- P6: Raj --------------------------------------------------------
    SHOE_DATA.Raj.regular     = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Raj\Shoe\raj_shoe_regular20260301-124939\RadarIfxAvian_00';
    SHOE_DATA.Raj.slow        = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Raj\Shoe\raj_shoe_slow20260301-125108\RadarIfxAvian_00';
    SHOE_DATA.Raj.fast        = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Raj\Shoe\raj_shoe_fast20260301-125306\RadarIfxAvian_00';
    SHOE_DATA.Raj.festination = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Raj\Shoe\raj_shoe_festination20260301-125440\RadarIfxAvian_00';
    SHOE_DATA.Raj.fog         = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Raj\Shoe\raj_shoe_fog20260301-125623\RadarIfxAvian_00';

    % ---- P7: Vijay ------------------------------------------------------
    SHOE_DATA.Vijay.regular     = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Vijay\Shoe\vijay_shoe_regular20260301-123648\RadarIfxAvian_00';
    SHOE_DATA.Vijay.slow        = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Vijay\Shoe\vijay_shoe_slow20260301-123906\RadarIfxAvian_00';
    SHOE_DATA.Vijay.fast        = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Vijay\Shoe\vijay_shoe_fast20260301-124040\RadarIfxAvian_00';
    SHOE_DATA.Vijay.festination = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Vijay\Shoe\vijay_shoe_festination20260301-124307\RadarIfxAvian_00';
    SHOE_DATA.Vijay.fog         = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Vijay\Shoe\vijay_shoe_fog20260301-124541\RadarIfxAvian_00';

    % ---- P8: Sudeep -----------------------------------------------------
    SHOE_DATA.Sudeep.regular     = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Sudeep\Shoe\sudeep_shoe_regular20260301-134107\RadarIfxAvian_00';
    SHOE_DATA.Sudeep.slow        = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Sudeep\Shoe\sudeep_shoe_slow20260301-134233\RadarIfxAvian_00';
    SHOE_DATA.Sudeep.fast        = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Sudeep\Shoe\sudeep_shoe_fast20260301-134417\RadarIfxAvian_00';
    SHOE_DATA.Sudeep.festination = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Sudeep\Shoe\sudeep_shoe_festination20260301-134847\RadarIfxAvian_00';
    SHOE_DATA.Sudeep.fog         = 'C:\Users\yoginathganditi\OneDrive - California State University, Sacramento\Documents\RadarFusionGUI\BGT60TR13C\Sudeep\Shoe\sudeep_shoe_fog20260301-135324\RadarIfxAvian_00';

    % =====================================================================
    % RESOLVE WHAT TO RUN
    % =====================================================================
    if RUN_ALL_SUBJECTS
        subjects_to_run = ALL_SUBJECTS;
    else
        subjects_to_run = {SUBJECT};
    end

    if strcmp(PATTERN, 'all')
        patterns_to_run = ALL_PATTERNS;
    else
        patterns_to_run = {PATTERN};
    end

    if strcmp(SENSOR, 'both')
        sensors_to_run = {'fixed', 'shoe'};
    else
        sensors_to_run = {SENSOR};
    end

    total_planned = length(subjects_to_run) * length(patterns_to_run) * length(sensors_to_run);
    fprintf('\n============================================================\n');
    fprintf('BATCH START: %d subject(s) x %d pattern(s) x %d sensor(s) = %d run(s)\n', ...
            length(subjects_to_run), length(patterns_to_run), length(sensors_to_run), total_planned);
    fprintf('Auto-zoom: window=%.1fs | steps=%d-%d | regularity_thr=%.2f\n', ...
            ZOOM_WINDOW_S, ZOOM_MIN_STEPS, ZOOM_MAX_STEPS, ZOOM_REGULARITY_THR);
    fprintf('Per-pattern thresholds (fixed): regular=%.2f  slow=%.2f  fast=%.2f  festination=%.2f  fog=%.2f\n', ...
            FIXED_THR.regular, FIXED_THR.slow, FIXED_THR.fast, FIXED_THR.festination, FIXED_THR.fog);
    fprintf('Per-pattern thresholds (shoe) : regular=%.2f  slow=%.2f  fast=%.2f  festination=%.2f  fog=%.2f\n', ...
            SHOE_THR.regular, SHOE_THR.slow, SHOE_THR.fast, SHOE_THR.festination, SHOE_THR.fog);
    fprintf('============================================================\n');

    % =====================================================================
    % MAIN LOOP
    % =====================================================================
    total_ok   = 0;
    failed_log = {};

    for si = 1:length(subjects_to_run)
        subj = subjects_to_run{si};

        for pi = 1:length(patterns_to_run)
            pat = patterns_to_run{pi};

            % ----------------------------------------------------------
            % Per-pattern auto-zoom settings
            % ----------------------------------------------------------
            switch pat
                case {'festination', 'fog'}
                    z_reg = 0.50;   % more irregular cadence — be lenient
                    z_max = 10;     % more steps may fit in 2s window
                    z_min = 3;
                case 'slow'
                    z_reg = 0.40;
                    z_max = 5;
                    z_min = 2;
                otherwise            % regular, fast
                    z_reg = ZOOM_REGULARITY_THR;
                    z_max = ZOOM_MAX_STEPS;
                    z_min = ZOOM_MIN_STEPS;
            end

            for sni = 1:length(sensors_to_run)
                sen = sensors_to_run{sni};

                fprintf('\n--- %s | %s | %s ---\n', subj, pat, upper(sen));

                try
                    if strcmp(sen, 'fixed')
                        thr   = FIXED_THR.(pat);
                        entry = FIXED_DATA.(subj).(pat);
                        dispatch_entry(entry, 'fixed', EMPTY_ROOM_PATH, ...
                            USE_SEGMENTS, SEGMENTS_MODE, STEP_MODE, ...
                            thr, DYNAMIC_GATE_HALFWIDTH_M, ...
                            SAVE_SEPARATE_PLOTS, SHOW_PLOTS, ...
                            ZOOM_WINDOW_S, z_min, z_max, z_reg, ZOOM_TIME_RANGE, ...
                            RUN_ALL_TRIALS_IF_LIST, TRIAL_INDEX_IF_LIST, subj, pat);
                    else
                        thr   = SHOE_THR.(pat);
                        entry = SHOE_DATA.(subj).(pat);
                        dispatch_entry(entry, 'shoe', '', ...
                            USE_SEGMENTS, SEGMENTS_MODE, STEP_MODE, ...
                            thr, 0, ...
                            SAVE_SEPARATE_PLOTS, SHOW_PLOTS, ...
                            ZOOM_WINDOW_S, z_min, z_max, z_reg, ZOOM_TIME_RANGE, ...
                            RUN_ALL_TRIALS_IF_LIST, TRIAL_INDEX_IF_LIST, subj, pat);
                    end

                    total_ok = total_ok + 1;
                    fprintf('  -> OK  (thr=%.2f m/s)\n', thr);

                catch ME
                    msg = sprintf('%s|%s|%s: %s', subj, pat, sen, ME.message);
                    fprintf('  -> FAILED: %s\n', ME.message);
                    failed_log{end+1} = msg; %#ok<AGROW>
                end
            end
        end
    end

    % =====================================================================
    % FINAL SUMMARY
    % =====================================================================
    fprintf('\n============================================================\n');
    fprintf('BATCH COMPLETE: %d/%d succeeded\n', total_ok, total_planned);
    if ~isempty(failed_log)
        fprintf('Failed runs (%d):\n', length(failed_log));
        for k = 1:length(failed_log)
            fprintf('  [%d] %s\n', k, failed_log{k});
        end
    else
        fprintf('All runs succeeded with no errors.\n');
    end
    fprintf('============================================================\n');
end


% =========================================================================
% INTERNAL: handle single-path OR cell-array entries
% =========================================================================
function dispatch_entry(entry, sensor_type, empty_path, ...
        use_segments, segments_mode, step_mode, ...
        min_step_height, dyn_gate, save_plots, show_plots, ...
        zoom_win, zoom_min, zoom_max, zoom_reg_thr, zoom_range, ...
        run_all, trial_idx, subject, pattern)

    paths = entry;
    if ~iscell(paths), paths = {paths}; end
    n = length(paths);

    if n > 1 && run_all
        fprintf('  %d trials for %s-%s (%s)\n', n, subject, pattern, upper(sensor_type));
        for i = 1:n
            fprintf('  Trial %d/%d...\n', i, n);
            try
                call_pipeline(char(paths{i}), sensor_type, empty_path, ...
                    use_segments, segments_mode, step_mode, min_step_height, ...
                    dyn_gate, save_plots, show_plots, ...
                    zoom_win, zoom_min, zoom_max, zoom_reg_thr, zoom_range);
                fprintf('  Trial %d: OK\n', i);
            catch ME
                fprintf('  Trial %d FAILED: %s\n', i, ME.message);
            end
        end
    else
        idx = min(max(trial_idx + 1, 1), n);
        call_pipeline(char(paths{idx}), sensor_type, empty_path, ...
            use_segments, segments_mode, step_mode, min_step_height, ...
            dyn_gate, save_plots, show_plots, ...
            zoom_win, zoom_min, zoom_max, zoom_reg_thr, zoom_range);
    end
end


% =========================================================================
% INTERNAL: call the appropriate pipeline function
% =========================================================================
function call_pipeline(walk_path, sensor_type, empty_path, ...
        use_segments, segments_mode, step_mode, min_step_height, ...
        dyn_gate, save_plots, show_plots, ...
        zoom_win, zoom_min, zoom_max, zoom_reg_thr, zoom_range)

    if strcmp(sensor_type, 'fixed')
        run_fixed(empty_path, walk_path, ...
            'frame_dt',                 0.078, ...
            'r_gate',                   [1.5, 7.0], ...
            'show',                     show_plots, ...
            'use_segments',             use_segments, ...
            'segments_mode',            segments_mode, ...
            'segment_pad_s',            0.30, ...
            'dynamic_gate_halfwidth_m', dyn_gate, ...
            'step_min_toe_mps',         min_step_height, ...
            'step_mode',                step_mode, ...
            'save_separate_plots',      save_plots, ...
            'zoom_time_range',          zoom_range, ...
            'zoom_window_s',            zoom_win, ...
            'zoom_min_steps',           zoom_min, ...
            'zoom_max_steps',           zoom_max, ...
            'zoom_regularity_thr',      zoom_reg_thr);
    else
        run_shoe_mounted(walk_path, ...
            'r_gate',                   [0.10, 1.20], ...
            'show',                     show_plots, ...
            'use_segments',             use_segments, ...
            'segments_mode',            segments_mode, ...
            'segment_pad_s',            0.25, ...
            'step_mode',                step_mode, ...
            'min_step_height_mps',      min_step_height, ...
            'height_prc',               10, ...
            'save_separate_plots',      save_plots, ...
            'zoom_time_range',          zoom_range, ...
            'zoom_window_s',            zoom_win, ...
            'zoom_min_steps',           zoom_min, ...
            'zoom_max_steps',           zoom_max, ...
            'zoom_regularity_thr',      zoom_reg_thr);
    end
end