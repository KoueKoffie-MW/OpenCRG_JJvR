%% CRG_DEMO_CREATE_SURFACE_BUNDLE
% Create a self-contained OpenCRG surface bundle from a road CRG file.

clearvars;

demoFolder = fileparts(mfilename("fullpath"));
repositoryFolder = fileparts(fileparts(demoFolder));
addpath(fullfile(repositoryFolder, "matlab", "lib"));
sourceFile = fullfile(repositoryFolder, "crg-txt", "handmade_curved.crg");
outputFolder = fullfile(tempdir, "OpenCRGSurfaceBundle");

[bundle, manifest] = crg_create_surface_bundle(sourceFile, outputFolder, ...
    BundleName="handmade_curved", NormalSmoothingSigma=[0.05 0.05]);
fprintf("Created bundle manifest: %s\n", bundle.ManifestFile);
fprintf("Road friction default: %.2f, off-road friction default: %.2f\n", ...
    manifest.Defaults.OnRoad.Friction, manifest.Defaults.OffRoad.Friction);
