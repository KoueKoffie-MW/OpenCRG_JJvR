function blockPath = crg_add_tire_plane_block(blockPath, crgFile, options)
%CRG_ADD_TIRE_PLANE_BLOCK Add a drop-in OpenCRG tire-plane subsystem.

arguments
    blockPath {mustBeTextScalar}
    crgFile {mustBeTextScalar}
    options.HistorySize (1, 1) double {mustBeInteger, mustBePositive} = 50
    options.Position (1, 4) double = [100 100 300 360]
    options.Replace (1, 1) logical = false
end

blockPath = string(blockPath);
crgFile = string(crgFile);

if getSimulinkBlockHandle(char(blockPath)) >= 0
    if ~options.Replace
        error("OpenCRG:tirePlaneBlockExists", ...
            "Block '%s' already exists. Use Replace=true to overwrite it.", blockPath);
    end
    delete_block(char(blockPath));
end

add_block("built-in/Subsystem", char(blockPath), Position=options.Position);
set_param(char(blockPath), TreatAsAtomicUnit="on");
localClearSubsystem(blockPath);

inputNames = ["x", "y", "pz_prev", "x_prev", "y_prev", "iu_prev"];
outputNames = ["px", "py", "pz", "iu_curr", "qx", "qy", "qz"];
inputX = 35;
outputX = 430;
sFunctionPath = blockPath + "/OpenCRG_TirePlane";

for inputIndex = 1:numel(inputNames)
    yPosition = 40 + 38*(inputIndex - 1);
    add_block("built-in/Inport", char(blockPath + "/" + inputNames(inputIndex)), ...
        Port=num2str(inputIndex), Position=[inputX yPosition inputX + 30 yPosition + 14]);
end

add_block("simulink/User-Defined Functions/S-Function", char(sFunctionPath), ...
    FunctionName="crg_sfun_tire_plane", ...
    Parameters=localParameterText(crgFile, options.HistorySize), ...
    Position=[185 65 315 275]);

for outputIndex = 1:numel(outputNames)
    yPosition = 30 + 34*(outputIndex - 1);
    add_block("built-in/Outport", char(blockPath + "/" + outputNames(outputIndex)), ...
        Port=num2str(outputIndex), Position=[outputX yPosition outputX + 30 yPosition + 14]);
end

for inputIndex = 1:numel(inputNames)
    add_line(char(blockPath), inputNames(inputIndex) + "/1", ...
        "OpenCRG_TirePlane/" + inputIndex, "autorouting", "on");
end

for outputIndex = 1:numel(outputNames)
    add_line(char(blockPath), "OpenCRG_TirePlane/" + outputIndex, ...
        outputNames(outputIndex) + "/1", "autorouting", "on");
end
end

function localClearSubsystem(blockPath)
try
    Simulink.SubSystem.deleteContents(char(blockPath));
catch
    childBlocks = string(find_system(char(blockPath), SearchDepth=1, Type="Block"));
    childBlocks(childBlocks == blockPath) = [];
    for childIndex = 1:numel(childBlocks)
        delete_block(char(childBlocks(childIndex)));
    end
end
end

function parameterText = localParameterText(crgFile, historySize)
escapedFile = replace(crgFile, "'", "''");
parameterText = char("'" + escapedFile + "', " + sprintf("%.15g", historySize));
end
