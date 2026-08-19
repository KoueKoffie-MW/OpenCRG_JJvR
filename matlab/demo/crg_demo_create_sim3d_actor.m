% Create a Simulink 3D Actor from handmade_curved.crg mesh data.

demoFolder = string(fileparts(mfilename("fullpath")));
matlabFolder = fileparts(demoFolder);
repo = fileparts(matlabFolder);
addpath(genpath(matlabFolder));

crgFile = fullfile(repo, "crg-txt", "handmade_curved.crg");

[actor, mesh] = crg_create_sim3d_actor(crgFile, ...
    ActorName="OpenCRG_HandmadeCurved", ...
    NumLongitudinalSamples=40, ...
    NumLateralSamples=9, ...
    PhysicsMesh=true);

disp(actor)
disp(mesh.Metadata)
