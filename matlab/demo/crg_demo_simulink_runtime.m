% Export and evaluate a CRG through the Simulink C runtime path.

demoFolder = string(fileparts(mfilename("fullpath")));
matlabFolder = fileparts(demoFolder);
repo = fileparts(matlabFolder);
addpath(genpath(matlabFolder));

crgFile = fullfile(repo, "crg-txt", "handmade_curved.crg");
runtimeFile = fullfile(tempdir, "handmade_curved_SimulinkRuntime.mat");

runtime = crg_export_simulink_runtime(crgFile, runtimeFile);
disp(runtime)

buildInfo = crg_build_simulink_runtime(Target="mex");
addpath(buildInfo.OutputFolder);

data = crg_read(crgFile);
uvQuery = [data.head.ubeg + 5*data.head.uinc, 0.0];
xyQuery = crg_eval_uv2xy(data, uvQuery);

runtimeHandle = crg_runtime_mex("open", crgFile, runtime.HistorySize);
cleanupRuntime = onCleanup(@() crg_runtime_mex("close", runtimeHandle));

[u, v, z, phi, curvature, status] = crg_runtime_mex("step", ...
    runtimeHandle, xyQuery(1), xyQuery(2), false);

table(u, v, z, phi, curvature, status)
