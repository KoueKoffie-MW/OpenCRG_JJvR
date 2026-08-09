%% CRG_DEMO_WRITE_RRHD
% Export handmade_curved.crg as a RoadRunner HD Map.

clearvars;

if exist('roadrunnerHDMap', 'file') ~= 2
    error('CRG:rrhdError', 'RoadRunner HD Map API is unavailable')
end

demoFolder = fileparts(mfilename('fullpath'));
repositoryFolder = fileparts(fileparts(demoFolder));
crgFile = fullfile(repositoryFolder, 'crg-txt', 'handmade_curved.crg');
singleLaneFile = fullfile(tempdir, 'handmade_curved_single_lane.rrhd');
lateralStripsFile = fullfile(tempdir, 'handmade_curved_lateral_strips.rrhd');

singleLaneMap = crg_write_rrhd(crgFile, singleLaneFile, NumSamples=100);
fprintf('Wrote %s with %d lane and %d boundaries.\n', ...
    singleLaneFile, numel(singleLaneMap.Lanes), numel(singleLaneMap.LaneBoundaries));

lateralStripsMap = crg_write_rrhd(crgFile, lateralStripsFile, ...
    Mode="LateralStrips", NumSamples=100);
fprintf('Wrote %s with %d lanes and %d boundaries.\n', ...
    lateralStripsFile, numel(lateralStripsMap.Lanes), numel(lateralStripsMap.LaneBoundaries));
