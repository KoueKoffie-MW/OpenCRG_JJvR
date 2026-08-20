function [bundle, manifest] = crg_create_surface_bundle(sourceFile, outputFolder, options)
%CRG_CREATE_SURFACE_BUNDLE Create a self-contained OpenCRG surface bundle.

arguments
    sourceFile {mustBeTextScalar}
    outputFolder {mustBeTextScalar}
    options.BundleName (1, 1) string = ""
    options.DataFormat (1, 1) string = "KRBI"
    options.Overwrite (1, 1) logical = false
    options.NormalSmoothingSigma (1, 2) double {mustBeNonnegative} = [0 0]
    options.ClosedTrack (1, 1) string = "auto"
    options.DefaultBlendWidth (1, 1) double {mustBePositive} = 2.0
    options.OnRoadFriction (1, 1) double = 1.0
    options.OffRoadFriction (1, 1) double = 0.7
    options.OnRoadMaterialId (1, 1) double {mustBeInteger, mustBePositive} = 1
    options.OffRoadMaterialId (1, 1) double {mustBeInteger, mustBePositive} = 2
    options.OnRoadRoughness (1, 1) double = 0.0
    options.OffRoadRoughness (1, 1) double = 0.0
    options.OnRoadWetness (1, 1) double = 0.0
    options.OffRoadWetness (1, 1) double = 0.0
    options.OnRoadTemperatureC (1, 1) double = 25.0
    options.OffRoadTemperatureC (1, 1) double = 25.0
    options.OnRoadRollingResistance (1, 1) double {mustBeNonnegative} = 0.015
    options.OffRoadRollingResistance (1, 1) double {mustBeNonnegative} = 0.015
end

sourceFile = string(sourceFile);
outputFolder = string(outputFolder);
if ~isfile(sourceFile)
    error("CRG:surfaceBundleError", "Source CRG file does not exist: %s", sourceFile)
end
if ~isfolder(outputFolder)
    mkdir(outputFolder)
end

dataFormat = validatestring(options.DataFormat, ["KRBI", "LRFI"]);
closedTrackMode = validatestring(lower(options.ClosedTrack), ["auto", "true", "false"]);
[~, sourceName] = fileparts(sourceFile);
bundleName = localBundleName(options.BundleName, sourceName);
paths = localBundlePaths(outputFolder, bundleName);
localVerifyOutputPaths(paths, sourceFile, options.Overwrite);

data = crg_check(crg_read(sourceFile));
if ~isfield(data, "ok")
    error("CRG:surfaceBundleError", "Source CRG data check was not successful.")
end

isClosedTrack = localResolveClosedTrack(data, closedTrackMode);
[normalX, normalY, normalZ] = localSurfaceNormals(data, options.NormalSmoothingSigma, isClosedTrack);
gridSize = size(data.z);
fieldGrids = struct( ...
    "Friction", single(options.OnRoadFriction*ones(gridSize)), ...
    "NormalX", single(normalX), ...
    "NormalY", single(normalY), ...
    "NormalZ", single(normalZ), ...
    "MaterialId", single(options.OnRoadMaterialId*ones(gridSize)), ...
    "Roughness", single(options.OnRoadRoughness*ones(gridSize)), ...
    "Wetness", single(options.OnRoadWetness*ones(gridSize)), ...
    "TemperatureC", single(options.OnRoadTemperatureC*ones(gridSize)), ...
    "RollingResistance", single(options.OnRoadRollingResistance*ones(gridSize)));

if ~localSameFile(sourceFile, paths.Road)
    [success, message] = copyfile(sourceFile, paths.Road);
    if ~success
        error("CRG:surfaceBundleError", "Could not copy source CRG: %s", message)
    end
end

localWriteProperty(data, paths.Friction, fieldGrids.Friction, "friction", "1", dataFormat)
localWriteProperty(data, paths.NormalX, fieldGrids.NormalX, "normal x", "1", dataFormat)
localWriteProperty(data, paths.NormalY, fieldGrids.NormalY, "normal y", "1", dataFormat)
localWriteProperty(data, paths.NormalZ, fieldGrids.NormalZ, "normal z", "1", dataFormat)
localWriteProperty(data, paths.MaterialId, fieldGrids.MaterialId, "material identifier", "1", dataFormat)
localWriteProperty(data, paths.Roughness, fieldGrids.Roughness, "roughness", "1", dataFormat)
localWriteProperty(data, paths.Wetness, fieldGrids.Wetness, "wetness", "1", dataFormat)
localWriteProperty(data, paths.TemperatureC, fieldGrids.TemperatureC, "temperature", "degC", dataFormat)
localWriteProperty(data, paths.RollingResistance, fieldGrids.RollingResistance, ...
    "rolling resistance coefficient", "1", dataFormat)

manifest = localManifest(paths, bundleName, sourceFile, data, options, dataFormat, isClosedTrack);
localWriteManifest(paths.Manifest, manifest)

bundle = struct( ...
    "Folder", outputFolder, ...
    "ManifestFile", paths.Manifest, ...
    "RoadFile", paths.Road, ...
    "Files", paths, ...
    "Defaults", manifest.Defaults, ...
    "NormalSmoothingSigma", options.NormalSmoothingSigma, ...
    "ClosedTrack", isClosedTrack);
end

function bundleName = localBundleName(requestedName, sourceName)
bundleName = string(requestedName);
if bundleName == ""
    bundleName = string(sourceName);
end
if endsWith(bundleName, "_road")
    bundleName = extractBefore(bundleName, strlength(bundleName) - strlength("_road") + 1);
end
if bundleName == ""
    error("CRG:surfaceBundleError", "BundleName must contain at least one character.")
end
end

function paths = localBundlePaths(outputFolder, bundleName)
paths = struct( ...
    "Road", fullfile(outputFolder, bundleName + "_road.crg"), ...
    "Friction", fullfile(outputFolder, bundleName + "_friction.crg"), ...
    "NormalX", fullfile(outputFolder, bundleName + "_nx.crg"), ...
    "NormalY", fullfile(outputFolder, bundleName + "_ny.crg"), ...
    "NormalZ", fullfile(outputFolder, bundleName + "_nz.crg"), ...
    "MaterialId", fullfile(outputFolder, bundleName + "_material_id.crg"), ...
    "Roughness", fullfile(outputFolder, bundleName + "_roughness.crg"), ...
    "Wetness", fullfile(outputFolder, bundleName + "_wetness.crg"), ...
    "TemperatureC", fullfile(outputFolder, bundleName + "_temperature_c.crg"), ...
    "RollingResistance", fullfile(outputFolder, bundleName + "_rolling_resistance.crg"), ...
    "Manifest", fullfile(outputFolder, bundleName + ".opencrg-bundle.json"));
end

function localVerifyOutputPaths(paths, sourceFile, overwrite)
pathNames = fieldnames(paths);
for pathIndex = 1:numel(pathNames)
    pathValue = string(paths.(pathNames{pathIndex}));
    if localSameFile(pathValue, sourceFile)
        continue
    end
    if isfile(pathValue) && ~overwrite
        error("CRG:surfaceBundleError", ...
            "Output already exists. Set Overwrite=true to replace it: %s", pathValue)
    end
end
end

function tf = localSameFile(firstPath, secondPath)
tf = strcmpi(char(java.io.File(char(firstPath)).getCanonicalPath()), ...
    char(java.io.File(char(secondPath)).getCanonicalPath()));
end

function isClosedTrack = localResolveClosedTrack(data, mode)
canClose = isfield(data, "dved") && isfield(data.dved, "ulex") && data.dved.ulex > 0;
switch mode
    case "auto"
        isClosedTrack = canClose && isfield(data, "opts") && isfield(data.opts, "rflc") && data.opts.rflc == 1;
    case "true"
        if ~canClose
            error("CRG:surfaceBundleError", "ClosedTrack=true requires a closable CRG reference line.")
        end
        isClosedTrack = true;
    otherwise
        isClosedTrack = false;
end
end

function [normalX, normalY, normalZ] = localSurfaceNormals(data, sigma, isClosedTrack)
uValues = localUValues(data);
vValues = localVValues(data);
[uGrid, vGrid] = ndgrid(uValues, vValues);
[xyValues, data] = crg_eval_uv2xy(data, [uGrid(:), vGrid(:)]);
[zValues, ~] = crg_eval_uv2z(data, [uGrid(:), vGrid(:)]);
vertices = cat(3, reshape(xyValues(:, 1), size(uGrid)), reshape(xyValues(:, 2), size(uGrid)), ...
    reshape(zValues, size(uGrid)));

normalX = zeros(size(uGrid));
normalY = zeros(size(uGrid));
normalZ = zeros(size(uGrid));
for rowIndex = 1:(size(uGrid, 1)-1)
    for columnIndex = 1:(size(uGrid, 2)-1)
        first = squeeze(vertices(rowIndex, columnIndex, :)).';
        second = squeeze(vertices(rowIndex+1, columnIndex, :)).';
        third = squeeze(vertices(rowIndex, columnIndex+1, :)).';
        fourth = squeeze(vertices(rowIndex+1, columnIndex+1, :)).';
        [normalX, normalY, normalZ] = localAccumulateTriangle( ...
            normalX, normalY, normalZ, [rowIndex columnIndex], [rowIndex+1 columnIndex], ...
            [rowIndex columnIndex+1], first, second, third);
        [normalX, normalY, normalZ] = localAccumulateTriangle( ...
            normalX, normalY, normalZ, [rowIndex+1 columnIndex], [rowIndex+1 columnIndex+1], ...
            [rowIndex columnIndex+1], second, fourth, third);
    end
end

[normalX, normalY, normalZ] = localNormalizeNormals(normalX, normalY, normalZ);
if any(sigma > 0)
    uIncrement = mean(diff(uValues));
    vIncrement = mean(diff(vValues));
    normalX = localSmoothGrid(normalX, sigma, [uIncrement vIncrement], isClosedTrack);
    normalY = localSmoothGrid(normalY, sigma, [uIncrement vIncrement], isClosedTrack);
    normalZ = localSmoothGrid(normalZ, sigma, [uIncrement vIncrement], isClosedTrack);
    [normalX, normalY, normalZ] = localNormalizeNormals(normalX, normalY, normalZ);
end
end

function [normalX, normalY, normalZ] = localAccumulateTriangle( ...
    normalX, normalY, normalZ, firstIndex, secondIndex, thirdIndex, first, second, third)
faceNormal = cross(second-first, third-first);
for vertexIndex = [firstIndex; secondIndex; thirdIndex].'
    normalX(vertexIndex(1), vertexIndex(2)) = normalX(vertexIndex(1), vertexIndex(2)) + faceNormal(1);
    normalY(vertexIndex(1), vertexIndex(2)) = normalY(vertexIndex(1), vertexIndex(2)) + faceNormal(2);
    normalZ(vertexIndex(1), vertexIndex(2)) = normalZ(vertexIndex(1), vertexIndex(2)) + faceNormal(3);
end
end

function [normalX, normalY, normalZ] = localNormalizeNormals(normalX, normalY, normalZ)
lengths = sqrt(normalX.^2 + normalY.^2 + normalZ.^2);
invalid = ~isfinite(lengths) | lengths <= eps;
lengths(invalid) = 1.0;
normalX = normalX./lengths;
normalY = normalY./lengths;
normalZ = normalZ./lengths;
normalX(invalid) = 0.0;
normalY(invalid) = 0.0;
normalZ(invalid) = 1.0;
downward = normalZ < 0;
normalX(downward) = -normalX(downward);
normalY(downward) = -normalY(downward);
normalZ(downward) = -normalZ(downward);
end

function smoothed = localSmoothGrid(values, sigma, increments, isClosedTrack)
smoothed = values;
for dimension = 1:2
    if sigma(dimension) <= 0
        continue
    end
    standardDeviation = sigma(dimension)/max(increments(dimension), eps);
    radius = max(1, ceil(3*standardDeviation));
    kernelPositions = -radius:radius;
    kernel = exp(-0.5*(kernelPositions/standardDeviation).^2);
    kernel = kernel/sum(kernel);
    if dimension == 1
        indices = localPaddedIndices(size(smoothed, 1), radius, isClosedTrack);
        smoothed = conv2(smoothed(indices, :), kernel(:), "valid");
    else
        indices = localPaddedIndices(size(smoothed, 2), radius, false);
        smoothed = conv2(smoothed(:, indices), kernel(:).', "valid");
    end
end
end

function indices = localPaddedIndices(valueCount, radius, useWrap)
indices = zeros(1, valueCount + 2*radius);
for outputIndex = 1:numel(indices)
    inputIndex = outputIndex - radius;
    if useWrap
        indices(outputIndex) = mod(inputIndex-1, valueCount) + 1;
    else
        while inputIndex < 1 || inputIndex > valueCount
            if inputIndex < 1
                inputIndex = 2 - inputIndex;
            else
                inputIndex = 2*valueCount - inputIndex;
            end
        end
        indices(outputIndex) = inputIndex;
    end
end
end

function values = localUValues(data)
values = data.head.ubeg + (0:(size(data.z, 1)-1)).'*data.head.uinc;
end

function values = localVValues(data)
if isfield(data, "v") && numel(data.v) == size(data.z, 2)
    values = double(data.v(:));
elseif isfield(data.head, "vinc") && data.head.vinc ~= 0
    values = data.head.vmin + (0:(size(data.z, 2)-1)).'*data.head.vinc;
else
    values = linspace(data.head.vmin, data.head.vmax, size(data.z, 2)).';
end
end

function localWriteProperty(sourceData, fileName, grid, quantity, unit, dataFormat)
propertyData = sourceData;
propertyData.filenm = fileName;
propertyData.z = single(grid);
propertyData.ct = { ...
    "OpenCRG surface bundle extension file.", ...
    sprintf("Quantity: %s", quantity), ...
    sprintf("Unit: %s", unit), ...
    "Interpret values using the adjacent OpenCRG bundle manifest."};
crg_write(crg_single(propertyData), fileName, dataFormat)
end

function manifest = localManifest(paths, bundleName, sourceFile, data, options, dataFormat, isClosedTrack)
manifest = struct;
manifest.SchemaVersion = 1;
manifest.BundleName = bundleName;
manifest.Generator = "crg_create_surface_bundle";
manifest.CreatedAt = char(datetime("now", Format="yyyy-MM-dd'T'HH:mm:ssXXX"));
manifest.SourceFile = sourceFile;
manifest.RoadFile = localFileName(paths.Road);
manifest.DataFormat = dataFormat;
manifest.ClosedTrack = isClosedTrack;
manifest.DefaultBlendWidth = options.DefaultBlendWidth;
manifest.Grid = struct( ...
    "NumU", size(data.z, 1), ...
    "NumV", size(data.z, 2), ...
    "UBegin", data.head.ubeg, ...
    "UEnd", data.head.uend, ...
    "VMin", data.head.vmin, ...
    "VMax", data.head.vmax);
manifest.Normal = struct( ...
    "CoordinateFrame", "global_xyz", ...
    "SmoothingMethod", "gaussian", ...
    "SmoothingSigma", options.NormalSmoothingSigma, ...
    "UpwardOrientation", true);
manifest.Defaults = struct( ...
    "OnRoad", localDefaults(options, "OnRoad"), ...
    "OffRoad", localDefaults(options, "OffRoad"));
manifest.Fields = struct( ...
    "Friction", localField(paths.Friction, "1", "linear"), ...
    "NormalX", localField(paths.NormalX, "1", "linear"), ...
    "NormalY", localField(paths.NormalY, "1", "linear"), ...
    "NormalZ", localField(paths.NormalZ, "1", "linear"), ...
    "MaterialId", localField(paths.MaterialId, "1", "nearest"), ...
    "Roughness", localField(paths.Roughness, "1", "linear"), ...
    "Wetness", localField(paths.Wetness, "1", "linear"), ...
    "TemperatureC", localField(paths.TemperatureC, "degC", "linear"), ...
    "RollingResistance", localField(paths.RollingResistance, "1", "linear"));
end

function values = localDefaults(options, prefix)
values = struct( ...
    "Friction", options.(prefix + "Friction"), ...
    "MaterialId", options.(prefix + "MaterialId"), ...
    "Roughness", options.(prefix + "Roughness"), ...
    "Wetness", options.(prefix + "Wetness"), ...
    "TemperatureC", options.(prefix + "TemperatureC"), ...
    "RollingResistance", options.(prefix + "RollingResistance"));
end

function field = localField(fileName, unit, interpolation)
field = struct("File", localFileName(fileName), "Unit", unit, "Interpolation", interpolation);
end

function fileName = localFileName(pathValue)
[~, name, extension] = fileparts(pathValue);
fileName = name + extension;
end

function localWriteManifest(fileName, manifest)
fileIdentifier = fopen(fileName, "w", "n", "UTF-8");
if fileIdentifier < 0
    error("CRG:surfaceBundleError", "Could not open manifest for writing: %s", fileName)
end
cleanup = onCleanup(@() fclose(fileIdentifier));
fprintf(fileIdentifier, "%s\n", jsonencode(manifest, PrettyPrint=true));
clear cleanup
end
