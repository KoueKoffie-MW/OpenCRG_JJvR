function [u, v, z, phi, curvature, status] = crg_runtime_xy2z_file(fileName, x, y, reset, historySize) %#codegen
%CRG_RUNTIME_XY2Z_FILE Evaluate OpenCRG z and road metadata for scalar x/y.

arguments
    fileName (1, :) char
    x (1, 1) double
    y (1, 1) double
    reset (1, 1) logical = false
    historySize (1, 1) double = 50
end

persistent isInitialized
coder.extrinsic("crg_runtime_source_info");

if coder.target("MATLAB")
    [u, v, z, phi, curvature, status] = crgRuntimeMatlabStep(fileName, x, y, reset, historySize);
else
    coder.cinclude("crg_runtime.h");
    sourceInfo = coder.const(feval("crg_runtime_source_info"));

    for includeIndex = coder.unroll(1:numel(sourceInfo.IncludePaths))
        coder.updateBuildInfo("addIncludePaths", sourceInfo.IncludePaths{includeIndex});
    end
    coder.updateBuildInfo("addSourceFiles", sourceInfo.RuntimeSource);
    for sourceIndex = coder.unroll(1:numel(sourceInfo.OpenCrgSources))
        coder.updateBuildInfo("addSourceFiles", sourceInfo.OpenCrgSources{sourceIndex});
    end

    u = 0.0;
    v = 0.0;
    z = 0.0;
    phi = 0.0;
    curvature = 0.0;
    status = int32(0);

    if isempty(isInitialized)
        nullTerminatedFileName = [fileName char(0)];
        initializeStatus = int32(0);
        initializeStatus = coder.ceval("crgRuntimeSingletonInitializeFromFile", ...
            coder.rref(nullTerminatedFileName), int32(historySize), int32(0));
        if initializeStatus ~= 0
            status = initializeStatus;
            return
        end
        isInitialized = true;
    end

    status = coder.ceval("crgRuntimeSingletonStepXY", x, y, int32(reset), ...
        coder.wref(u), coder.wref(v), coder.wref(z), coder.wref(phi), coder.wref(curvature));
end
end

function [u, v, z, phi, curvature, status] = crgRuntimeMatlabStep(fileName, x, y, reset, historySize)
persistent runtimeHandle runtimeFile runtimeData

if exist("crg_runtime_mex", "file") == 3
    if isempty(runtimeHandle) || ~strcmp(runtimeFile, fileName)
        if ~isempty(runtimeHandle)
            crg_runtime_mex("close", runtimeHandle);
        end
        runtimeHandle = crg_runtime_mex("open", fileName, historySize);
        runtimeFile = fileName;
    end
    [u, v, z, phi, curvature, status] = crg_runtime_mex("step", runtimeHandle, x, y, reset);
    status = int32(status);
    return
end

if isempty(runtimeData) || reset || ~strcmp(runtimeFile, fileName)
    runtimeData = crg_read(fileName);
    runtimeFile = fileName;
end

[uv, runtimeData] = crg_eval_xy2uv(runtimeData, [x y]);
[zValue, runtimeData] = crg_eval_uv2z(runtimeData, uv);
[phiValue, runtimeData] = crg_eval_u2phi(runtimeData, uv(1));
[curvatureValue, runtimeData] = crg_eval_u2crv(runtimeData, uv(1));

u = uv(1);
v = uv(2);
z = zValue(1);
phi = phiValue(1);
curvature = curvatureValue(1);
status = int32(0);
end
