function [road, metadata] = crg_export_road_surface_lookup(source, matFile, options)
%CRG_EXPORT_ROAD_SURFACE_LOOKUP Export matched CRG road/friction/normal lookup data.

arguments
    source
    matFile {mustBeTextScalar} = ""
    options.Precision (1, 1) string = "single"
    options.IncludeFriction (1, 1) logical = true
    options.IncludeNormals (1, 1) logical = true
    options.RequireMatchedFiles (1, 1) logical = false
    options.FrictionFile (1, 1) string = ""
    options.NormalXFile (1, 1) string = ""
    options.NormalYFile (1, 1) string = ""
    options.NormalZFile (1, 1) string = ""
    options.LocalSearchRadius (1, 1) double {mustBeInteger, mustBePositive} = 25
    options.CoarseSearchStride (1, 1) double {mustBeInteger, mustBePositive} = 25
    options.CoarseRefineRadius (1, 1) double {mustBeInteger, mustBePositive} = 50
    options.MaxLocalDistance (1, 1) double = Inf
    options.Write (1, 1) logical = true
end

precision = validatestring(options.Precision, ["single", "double"]);
[road, metadata] = crg_export_tire_plane_lookup(source, "", ...
    Precision=precision, ...
    LocalSearchRadius=options.LocalSearchRadius, ...
    CoarseSearchStride=options.CoarseSearchStride, ...
    CoarseRefineRadius=options.CoarseRefineRadius, ...
    MaxLocalDistance=options.MaxLocalDistance, ...
    Write=false);

sourceFile = string(metadata.SourceFile);
matchedFiles = localMatchedFiles(sourceFile, options);
road.hasFriction = 0.0;
road.hasNormals = 0.0;
road.friction = localCast(ones(size(road.z)), precision);
road.normalX = localCast(zeros(size(road.z)), precision);
road.normalY = localCast(zeros(size(road.z)), precision);
road.normalZ = localCast(ones(size(road.z)), precision);

if options.IncludeFriction
    [frictionGrid, frictionFile] = localReadOptionalGrid(matchedFiles.Friction, road, precision, ...
        options.RequireMatchedFiles, "friction");
    if frictionFile ~= ""
        road.friction = frictionGrid;
        road.hasFriction = 1.0;
        matchedFiles.Friction = frictionFile;
    end
end

if options.IncludeNormals
    [normalXGrid, normalXFile] = localReadOptionalGrid(matchedFiles.NormalX, road, precision, ...
        options.RequireMatchedFiles, "normal X");
    [normalYGrid, normalYFile] = localReadOptionalGrid(matchedFiles.NormalY, road, precision, ...
        options.RequireMatchedFiles, "normal Y");
    [normalZGrid, normalZFile] = localReadOptionalGrid(matchedFiles.NormalZ, road, precision, ...
        options.RequireMatchedFiles, "normal Z");
    if normalXFile ~= "" && normalYFile ~= "" && normalZFile ~= ""
        road.normalX = normalXGrid;
        road.normalY = normalYGrid;
        road.normalZ = normalZGrid;
        road.hasNormals = 1.0;
        matchedFiles.NormalX = normalXFile;
        matchedFiles.NormalY = normalYFile;
        matchedFiles.NormalZ = normalZFile;
    elseif options.RequireMatchedFiles
        error("CRG:roadSurfaceLookupError", "All normal CRG files are required when IncludeNormals is true.")
    end
end

metadata.RuntimeFunction = "crg_road_surface_lookup_step";
metadata.Outputs = ["px", "py", "pz", "iu_curr", "qx", "qy", "qz", "mu"];
metadata.MatchedFiles = matchedFiles;
metadata.HasFriction = road.hasFriction ~= 0.0;
metadata.HasNormals = road.hasNormals ~= 0.0;
metadata.ApproxBytes = localApproxBytes(road);

if options.Write
    if matFile == ""
        if sourceFile == ""
            error("CRG:roadSurfaceLookupError", ...
                "MATFILE is required when SOURCE does not provide a file name.")
        end
        [folder, name] = fileparts(sourceFile);
        matFile = fullfile(folder, name + "_RoadSurfaceLookup.mat");
    end
    save(matFile, "road", "metadata", "-v7.3");
end
end

function matchedFiles = localMatchedFiles(sourceFile, options)
matchedFiles = struct("Road", sourceFile, "Friction", "", "NormalX", "", "NormalY", "", "NormalZ", "");
if sourceFile ~= ""
    matchedFiles.Friction = localSiblingFile(sourceFile, "_friction");
    matchedFiles.NormalX = localSiblingFile(sourceFile, "_nx");
    matchedFiles.NormalY = localSiblingFile(sourceFile, "_ny");
    matchedFiles.NormalZ = localSiblingFile(sourceFile, "_nz");
end
if options.FrictionFile ~= ""
    matchedFiles.Friction = options.FrictionFile;
end
if options.NormalXFile ~= ""
    matchedFiles.NormalX = options.NormalXFile;
end
if options.NormalYFile ~= ""
    matchedFiles.NormalY = options.NormalYFile;
end
if options.NormalZFile ~= ""
    matchedFiles.NormalZ = options.NormalZFile;
end
end

function siblingFile = localSiblingFile(sourceFile, suffix)
[folder, name, extension] = fileparts(sourceFile);
baseName = string(name);
if endsWith(baseName, "_road")
    baseName = extractBefore(baseName, strlength(baseName) - strlength("_road") + 1);
end
siblingFile = fullfile(folder, baseName + suffix + extension);
end

function [grid, fileName] = localReadOptionalGrid(fileName, road, precision, isRequired, label)
grid = localCast(zeros(size(road.z)), precision);
fileName = string(fileName);
if fileName == "" || ~isfile(fileName)
    if isRequired
        error("CRG:roadSurfaceLookupError", "Missing %s CRG file: %s", label, fileName)
    end
    fileName = "";
    return
end

data = crg_read(fileName);
localVerifyCompatibleGrid(data, road, fileName);
grid = localCast(data.z, precision);
end

function localVerifyCompatibleGrid(data, road, fileName)
if ~isequal(size(data.z), size(road.z))
    error("CRG:roadSurfaceLookupError", "CRG grid size does not match road grid: %s", fileName)
end
if abs(double(data.head.ubeg) - road.uMin) > 1e-9 || abs(double(data.head.uinc) - road.uInc) > 1e-9
    error("CRG:roadSurfaceLookupError", "CRG u-axis does not match road grid: %s", fileName)
end
if abs(double(data.head.vmin) - road.vMin) > 1e-9 || abs(double(data.head.vmax) - road.vMax) > 1e-9
    error("CRG:roadSurfaceLookupError", "CRG v-axis does not match road grid: %s", fileName)
end
end

function values = localCast(values, precision)
if precision == "single"
    values = single(values);
else
    values = double(values);
end
end

function numBytes = localApproxBytes(road)
numBytes = 0;
fieldList = fieldnames(road);
for fieldIndex = 1:numel(fieldList)
    fieldValue = road.(fieldList{fieldIndex});
    numBytes = numBytes + numel(fieldValue)*localElementBytes(fieldValue);
end
end

function bytes = localElementBytes(value)
switch class(value)
    case {"double", "uint64", "int64"}
        bytes = 8;
    case {"single", "uint32", "int32"}
        bytes = 4;
    case {"uint16", "int16"}
        bytes = 2;
    otherwise
        bytes = 1;
end
end