function [bundle, metadata] = crg_export_surface_bundle_lookup(source, options)
%CRG_EXPORT_SURFACE_BUNDLE_LOOKUP Load an OpenCRG surface bundle for lookup.

arguments
    source {mustBeTextScalar}
    options.Precision (1, 1) string = "single"
end

precision = validatestring(options.Precision, ["single", "double"]);
manifestFile = localManifestFile(source);
bundleFolder = string(fileparts(manifestFile));
manifest = jsondecode(fileread(manifestFile));
roadFile = fullfile(bundleFolder, string(manifest.RoadFile));
[bundle, ~] = crg_export_tire_plane_lookup(roadFile, "", Precision=precision, Write=false);
bundle.RoadData = crg_check(crg_read(roadFile));
if ~isfield(bundle.RoadData, "ok")
    error("CRG:surfaceBundleError", "Bundle road data check was not successful.")
end

fieldNames = ["Friction", "NormalX", "NormalY", "NormalZ", "MaterialId", "Roughness", ...
    "Wetness", "TemperatureC", "RollingResistance"];
for fieldIndex = 1:numel(fieldNames)
    fieldName = fieldNames(fieldIndex);
    grid = localReadBundleGrid(bundleFolder, manifest.Fields.(fieldName), bundle);
    bundle.(localBundleFieldName(fieldName)) = localCast(grid, precision);
end

bundle.Defaults = manifest.Defaults;
bundle.BlendWidth = double(manifest.DefaultBlendWidth);
bundle.IsClosedTrack = double(manifest.ClosedTrack);
bundle.Boundary = localBoundary(bundle.RoadData, logical(bundle.IsClosedTrack));
metadata = struct( ...
    "ManifestFile", manifestFile, ...
    "RoadFile", roadFile, ...
    "SchemaVersion", manifest.SchemaVersion, ...
    "BundleName", string(manifest.BundleName), ...
    "ClosedTrack", logical(bundle.IsClosedTrack), ...
    "GridSize", size(bundle.z));
end

function manifestFile = localManifestFile(source)
source = string(source);
if isfolder(source)
    manifestFiles = dir(fullfile(source, "*.opencrg-bundle.json"));
    if numel(manifestFiles) ~= 1
        error("CRG:surfaceBundleError", ...
            "Bundle folder must contain exactly one .opencrg-bundle.json manifest.")
    end
    manifestFile = fullfile(manifestFiles.folder, manifestFiles.name);
else
    manifestFile = source;
end
if ~isfile(manifestFile)
    error("CRG:surfaceBundleError", "Bundle manifest does not exist: %s", manifestFile)
end
end

function grid = localReadBundleGrid(bundleFolder, fieldInfo, road)
fileName = fullfile(bundleFolder, string(fieldInfo.File));
if ~isfile(fileName)
    error("CRG:surfaceBundleError", "Bundle field file does not exist: %s", fileName)
end
data = crg_read(fileName);
if ~isequal(size(data.z), size(road.z))
    error("CRG:surfaceBundleError", "Bundle field grid size does not match the road grid: %s", fileName)
end
if abs(double(data.head.ubeg) - road.uMin) > 1e-9 || abs(double(data.head.uinc) - road.uInc) > 1e-9 || ...
        abs(double(data.head.vmin) - road.vMin) > 1e-9 || abs(double(data.head.vmax) - road.vMax) > 1e-9
    error("CRG:surfaceBundleError", "Bundle field grid coordinates do not match the road grid: %s", fileName)
end
grid = data.z;
end

function fieldName = localBundleFieldName(manifestFieldName)
switch manifestFieldName
    case "Friction"
        fieldName = "friction";
    case "NormalX"
        fieldName = "normalX";
    case "NormalY"
        fieldName = "normalY";
    case "NormalZ"
        fieldName = "normalZ";
    case "MaterialId"
        fieldName = "materialId";
    case "Roughness"
        fieldName = "roughness";
    case "Wetness"
        fieldName = "wetness";
    case "TemperatureC"
        fieldName = "temperatureC";
    otherwise
        fieldName = "rollingResistance";
end
end

function values = localCast(values, precision)
if precision == "single"
    values = single(values);
else
    values = double(values);
end
end

function boundary = localBoundary(data, isClosedTrack)
uValues = data.head.ubeg + (0:(size(data.z, 1)-1)).'*data.head.uinc;
rightUv = [uValues repmat(data.head.vmin, numel(uValues), 1)];
leftUv = [uValues repmat(data.head.vmax, numel(uValues), 1)];
[rightXy, ~] = crg_eval_uv2xy(data, rightUv);
[leftXy, ~] = crg_eval_uv2xy(data, leftUv);

segmentCount = 2*(numel(uValues)-1) + 2*double(isClosedTrack) + 2*double(~isClosedTrack);
boundary = struct( ...
    "X1", zeros(segmentCount, 1), "Y1", zeros(segmentCount, 1), ...
    "X2", zeros(segmentCount, 1), "Y2", zeros(segmentCount, 1), ...
    "U1", zeros(segmentCount, 1), "V1", zeros(segmentCount, 1), ...
    "U2", zeros(segmentCount, 1), "V2", zeros(segmentCount, 1));
segmentIndex = 0;
[boundary, segmentIndex] = localAddSegments(boundary, segmentIndex, rightXy, rightUv, false);
[boundary, segmentIndex] = localAddSegments(boundary, segmentIndex, leftXy, leftUv, false);
if isClosedTrack
    [boundary, segmentIndex] = localAddSegment(boundary, segmentIndex, rightXy(end, :), rightUv(end, :), rightXy(1, :), rightUv(1, :));
    [boundary, ~] = localAddSegment(boundary, segmentIndex, leftXy(end, :), leftUv(end, :), leftXy(1, :), leftUv(1, :));
else
    [boundary, segmentIndex] = localAddSegment(boundary, segmentIndex, rightXy(1, :), rightUv(1, :), leftXy(1, :), leftUv(1, :));
    [boundary, ~] = localAddSegment(boundary, segmentIndex, rightXy(end, :), rightUv(end, :), leftXy(end, :), leftUv(end, :));
end
end

function [boundary, segmentIndex] = localAddSegments(boundary, segmentIndex, xy, uv, reverseOrder)
if reverseOrder
    xy = flipud(xy);
    uv = flipud(uv);
end
for pointIndex = 1:(size(xy, 1)-1)
    [boundary, segmentIndex] = localAddSegment(boundary, segmentIndex, xy(pointIndex, :), uv(pointIndex, :), ...
        xy(pointIndex+1, :), uv(pointIndex+1, :));
end
end

function [boundary, segmentIndex] = localAddSegment(boundary, segmentIndex, xy1, uv1, xy2, uv2)
segmentIndex = segmentIndex + 1;
boundary.X1(segmentIndex) = xy1(1);
boundary.Y1(segmentIndex) = xy1(2);
boundary.X2(segmentIndex) = xy2(1);
boundary.Y2(segmentIndex) = xy2(2);
boundary.U1(segmentIndex) = uv1(1);
boundary.V1(segmentIndex) = uv1(2);
boundary.U2(segmentIndex) = uv2(1);
boundary.V2(segmentIndex) = uv2(2);
end
