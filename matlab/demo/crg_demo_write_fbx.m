% Export handmade_curved.crg as a physics-oriented FBX road mesh.

demoFolder = string(fileparts(mfilename("fullpath")));
matlabFolder = fileparts(demoFolder);
repo = fileparts(matlabFolder);
addpath(genpath(matlabFolder));

crgFile = fullfile(repo, "crg-txt", "handmade_curved.crg");
fbxFile = fullfile(tempdir, "handmade_curved_opencrg_physics.fbx");

[fbxFile, mesh] = crg_write_fbx(crgFile, fbxFile, ...
    NumLongitudinalSamples=40, ...
    NumLateralSamples=9, ...
    PhysicsMesh=true, ...
    Thickness=0.05);

disp(fbxFile)
disp(mesh.Metadata)
