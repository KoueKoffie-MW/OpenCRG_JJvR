function buildInfo = crg_build_simulink_runtime(options)
%CRG_BUILD_SIMULINK_RUNTIME Build OpenCRG C runtime MEX and S-Function.

arguments
    options.Target (1, 1) string = "all"
    options.OutputFolder (1, 1) string = ""
    options.Verbose (1, 1) logical = true
end

target = lower(validatestring(options.Target, ["all", "mex", "sfunction"]));
sourceInfo = crg_runtime_source_info();

if options.OutputFolder == ""
    outputFolder = fullfile(sourceInfo.SimulinkFolder, "bin");
else
    outputFolder = options.OutputFolder;
end

if ~isfolder(outputFolder)
    mkdir(outputFolder);
end

includeArguments = strcat("-I", string(sourceInfo.IncludePaths));
commonSources = [string(sourceInfo.RuntimeSource), string(sourceInfo.OpenCrgSources)];
buildInfo = struct( ...
    "OutputFolder", char(outputFolder), ...
    "MexFile", char(fullfile(outputFolder, "crg_runtime_mex." + mexext())), ...
    "SFunctionFile", char(fullfile(outputFolder, "crg_sfun_xy2z." + mexext())));

if target == "all" || target == "mex"
    if options.Verbose
        fprintf("Building crg_runtime_mex in %s\n", outputFolder);
    end
    mexArguments = ["-outdir", outputFolder, includeArguments, ...
        string(sourceInfo.MexSource), commonSources];
    mex(mexArguments{:});
end

if target == "all" || target == "sfunction"
    if options.Verbose
        fprintf("Building crg_sfun_xy2z in %s\n", outputFolder);
    end
    mexArguments = ["-outdir", outputFolder, includeArguments, ...
        string(sourceInfo.SFunctionSource), commonSources];
    mex(mexArguments{:});
end

if ~contains(string(path), string(outputFolder))
    addpath(outputFolder);
end
end
