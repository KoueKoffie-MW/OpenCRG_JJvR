%% CRG_DEMO_EXPORT_LOOKUP
% Export handmade_curved.crg as MATLAB and Simulink lookup-table variables.

clearvars;

demoFolder = fileparts(mfilename('fullpath'));
repositoryFolder = fileparts(fileparts(demoFolder));
crgFile = fullfile(repositoryFolder, 'crg-txt', 'handmade_curved.crg');
lookupFile = fullfile(tempdir, 'handmade_curved_Lookup.mat');

lookup = crg_export_lookup(crgFile, lookupFile, Channel="Elevation");
fprintf('Wrote %s with table size %dx%d and unit %s.\n', ...
    lookupFile, size(lookup.Table, 1), size(lookup.Table, 2), lookup.TableUnit);
