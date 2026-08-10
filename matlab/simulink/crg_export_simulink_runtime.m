function [runtime, lookup] = crg_export_simulink_runtime(source, matFile, options)
%CRG_EXPORT_SIMULINK_RUNTIME Export OpenCRG runtime variables for Simulink.
%   RUNTIME = CRG_EXPORT_SIMULINK_RUNTIME(SOURCE) prepares metadata for the
%   C API backed scalar OpenCRG runtime and lookup fallback variables.

arguments
    source
    matFile {mustBeTextScalar} = ""
    options.Channel (1, 1) string = "Elevation"
    options.ChannelUnit (1, 1) string = ""
    options.HistorySize (1, 1) double = 50
    options.SourceMode (1, 1) string = "Both"
    options.CreateSimulinkLookupTable (1, 1) logical = true
    options.Write (1, 1) logical = true
end

sourceMode = validatestring(options.SourceMode, ["File", "EmbeddedArrays", "Both"]);
[sourceFile, defaultMatFile] = crgRuntimeSourceFile(source);
if matFile == ""
    matFile = defaultMatFile;
end

[lookup, data] = crg_export_lookup(source, "", ...
    Channel=options.Channel, ...
    ChannelUnit=options.ChannelUnit, ...
    CreateSimulinkLookupTable=options.CreateSimulinkLookupTable, ...
    Write=false);

runtime = struct( ...
    "SourceFile", sourceFile, ...
    "SourceMode", string(sourceMode), ...
    "HistorySize", options.HistorySize, ...
    "Channel", options.Channel, ...
    "ChannelUnit", options.ChannelUnit, ...
    "SFunctionName", "crg_sfun_xy2z", ...
    "CodegenFunction", "crg_runtime_xy2z_file", ...
    "Outputs", ["u", "v", "z", "phi", "curvature", "status"], ...
    "Lookup", lookup, ...
    "GridSize", size(data.z), ...
    "URange", [data.head.ubeg data.head.uend], ...
    "VRange", [data.head.vmin data.head.vmax]);

if options.Write
    if matFile == ""
        error("CRG:runtimeError", "MATFILE is required when SOURCE does not provide a file name.")
    end
    u = lookup.Breakpoints1;
    v = lookup.Breakpoints2;
    tableData = lookup.Table;
    if isfield(lookup, "SimulinkLookupTable")
        simulinkLookupTable = lookup.SimulinkLookupTable;
    else
        simulinkLookupTable = [];
    end
    save(matFile, "runtime", "lookup", "u", "v", "tableData", "simulinkLookupTable");
end
end

function [sourceFile, matFile] = crgRuntimeSourceFile(source)
if isstruct(source)
    if isfield(source, "filenm")
        sourceFile = string(source.filenm);
    else
        sourceFile = "";
    end
else
    sourceFile = string(source);
end

if sourceFile == ""
    matFile = "";
else
    [folder, name] = fileparts(sourceFile);
    matFile = fullfile(folder, name + "_SimulinkRuntime.mat");
end
end
