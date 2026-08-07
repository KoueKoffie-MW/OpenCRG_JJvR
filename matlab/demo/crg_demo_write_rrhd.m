%% CRG_DEMO_WRITE_RRHD
% Export handmade_curved.crg as a RoadRunner HD Map.

clearvars;

if exist('roadrunnerHDMap', 'file') ~= 2
    error('CRG:rrhdError', 'RoadRunner HD Map API is unavailable')
end

demoFolder = fileparts(mfilename('fullpath'));
repositoryFolder = fileparts(fileparts(demoFolder));
crgFile = fullfile(repositoryFolder, 'crg-txt', 'handmade_curved.crg');
rrhdFile = fullfile(tempdir, 'handmade_curved.rrhd');

rrMap = crg_write_rrhd(crgFile, rrhdFile, NumSamples=100);
fprintf('Wrote %s with %d lane and %d boundaries.\n', ...
    rrhdFile, numel(rrMap.Lanes), numel(rrMap.LaneBoundaries));
