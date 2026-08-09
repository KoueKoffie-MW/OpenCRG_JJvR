%% CRG_DEMO_WRITE_SIMSCAPE_GRID
% Export handmade_curved.crg as Simscape Grid Surface variables.

clearvars;

demoFolder = fileparts(mfilename('fullpath'));
repositoryFolder = fileparts(fileparts(demoFolder));
crgFile = fullfile(repositoryFolder, 'crg-txt', 'handmade_curved.crg');
gridFile = fullfile(tempdir, 'handmade_curved_SimscapeGrid.mat');

[x, y, z] = crg_write_simscape_grid(crgFile, gridFile, GridResolution=0.5);
fprintf('Wrote %s with x=%d, y=%d, z=%dx%d.\n', ...
    gridFile, numel(x), numel(y), size(z, 1), size(z, 2));
