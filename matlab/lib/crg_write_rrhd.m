function [rrMap, data, geometry] = crg_write_rrhd(source, rrhdFile, options)
%CRG_WRITE_RRHD Export OpenCRG road data as RoadRunner HD Map.
%   RRMAP = CRG_WRITE_RRHD(SOURCE, RRHDFILE) reads OpenCRG data from SOURCE
%   and writes a RoadRunner HD Map file to RRHDFILE.
%
%   [RRMAP, DATA, GEOMETRY] = CRG_WRITE_RRHD(___) also returns the checked
%   OpenCRG data and the exported lane and boundary geometries.
%
%   SOURCE can be a CRG file name or a DATA struct as defined in CRG_INTRO.
%
%   Name-value options:
%       Mode                   "SingleLane" or "LateralStrips".
%       NumSamples             Number of longitudinal samples. Default uses CRG rows.
%       LaneVLimits            [right left] lateral offsets. Default uses CRG limits.
%       CenterV                Lane-center lateral offset for "SingleLane".
%       GeoReference           [latitude longitude] in degrees.
%       AddEdgeMarkings        Add edge markings where selected marking mode permits.
%       StripLaneType          Lane type for "LateralStrips" lanes.
%       StripBoundaryMarkings  "None", "OuterOnly", or "All".
%       EvalChunkSize          Maximum UV points per evaluation chunk.
%       Write                  Write RRHDFILE. Set false to build RRMAP only.
%
%   Example:
%       crg_write_rrhd("road.crg", "road.rrhd", Mode="LateralStrips")
%
%   See also CRG_READ, CRG_EVAL_UV2XY, CRG_EVAL_UV2Z.

arguments
    source
    rrhdFile {mustBeTextScalar} = ""
    options.Mode (1, 1) string = "SingleLane"
    options.NumSamples (1, 1) double {mustBeInteger, mustBeNonnegative} = 0
    options.LaneVLimits (1, 2) double = [NaN NaN]
    options.CenterV (1, 1) double = NaN
    options.GeoReference double = []
    options.LaneID (1, 1) string = "Lane1"
    options.LeftBoundaryID (1, 1) string = "Left"
    options.RightBoundaryID (1, 1) string = "Right"
    options.TravelDirection (1, 1) string = "Forward"
    options.LaneType (1, 1) string = "Driving"
    options.StripLaneType (1, 1) string = "Driving"
    options.StripBoundaryMarkings (1, 1) string = "OuterOnly"
    options.AddEdgeMarkings (1, 1) logical = true
    options.MarkingID (1, 1) string = "SolidWhite"
    options.MarkingAsset (1, 1) string = "Assets/Markings/SolidSingleWhite.rrlms"
    options.EvalChunkSize (1, 1) double {mustBeInteger, mustBePositive} = 250000
    options.Write (1, 1) logical = true
end

options = crgRrhdValidateOptions(options);
[data, sourceFile] = crgRrhdReadSource(source);
rrhdFile = crgRrhdOutputFile(rrhdFile, sourceFile, options.Write);
[geometry, data] = crgRrhdGeometry(data, options);
rrMap = crgRrhdMap(geometry, data, options);
crgRrhdValidate(rrMap);

if options.Write
    write(rrMap, rrhdFile);
end
end

function options = crgRrhdValidateOptions(options)
options.Mode = string(validatestring(options.Mode, ["SingleLane", "LateralStrips"]));
options.TravelDirection = string(validatestring(options.TravelDirection, ...
    ["Forward", "Backward", "Bidirectional", "Undirected"]));
options.LaneType = string(validatestring(options.LaneType, ...
    ["Driving", "Shoulder", "Biking", "Border", "Restricted", "Parking", "Curb", "Sidewalk", "CenterTurn"]));
options.StripLaneType = string(validatestring(options.StripLaneType, ...
    ["Driving", "Shoulder", "Biking", "Border", "Restricted", "Parking", "Curb", "Sidewalk", "CenterTurn"]));
options.StripBoundaryMarkings = string(validatestring(options.StripBoundaryMarkings, ...
    ["None", "OuterOnly", "All"]));
end

function [data, sourceFile] = crgRrhdReadSource(source)
if isstruct(source)
    data = source;
    if isfield(data, 'filenm')
        sourceFile = string(data.filenm);
    else
        sourceFile = "";
    end
else
    sourceFile = string(source);
    data = crg_read(sourceFile);
end

if ~isfield(data, 'ok')
    data = crg_check(data);
    if ~isfield(data, 'ok')
        error('CRG:rrhdError', 'check of DATA was not completely successful')
    end
end
end

function rrhdFile = crgRrhdOutputFile(rrhdFile, sourceFile, writeOutput)
rrhdFile = string(rrhdFile);
if rrhdFile == "" && writeOutput
    if sourceFile == ""
        error('CRG:rrhdError', 'RRHDFILE is required when SOURCE is a data struct and Write is true')
    end
    [folder, name] = fileparts(sourceFile);
    rrhdFile = fullfile(folder, name + ".rrhd");
end

if rrhdFile ~= ""
    [folder, name, extension] = fileparts(rrhdFile);
    if extension == ""
        rrhdFile = fullfile(folder, name + ".rrhd");
    end
end
end

function [geometry, data] = crgRrhdGeometry(data, options)
switch options.Mode
    case "SingleLane"
        [geometry, data] = crgRrhdSingleLaneGeometry(data, options);
    case "LateralStrips"
        [geometry, data] = crgRrhdStripGeometry(data, options);
    otherwise
        error('CRG:rrhdError', 'Unsupported RRHD export mode: %s', options.Mode)
end
end

function [geometry, data] = crgRrhdSingleLaneGeometry(data, options)
longitudinalPositions = crgRrhdLongitudinalPositions(data, options.NumSamples);
lateralLimits = crgRrhdLaneVLimits(data, options.LaneVLimits);
centerOffset = options.CenterV;
if isnan(centerOffset)
    centerOffset = crgRrhdCenterV(lateralLimits);
end
if centerOffset < min(lateralLimits) || centerOffset > max(lateralLimits)
    error('CRG:rrhdError', 'CenterV must lie inside LaneVLimits')
end

leftOffset = max(lateralLimits);
rightOffset = min(lateralLimits);
[polylines, data] = crgRrhdEvaluatePolylines(data, longitudinalPositions, ...
    [leftOffset centerOffset rightOffset], options.EvalChunkSize);

geometry.Mode = "SingleLane";
geometry.LeftBoundary = polylines{1};
geometry.CenterLine = polylines{2};
geometry.RightBoundary = polylines{3};
geometry.LongitudinalPositions = longitudinalPositions;
geometry.LaneVLimits = [rightOffset leftOffset];
geometry.CenterV = centerOffset;
end

function [geometry, data] = crgRrhdStripGeometry(data, options)
longitudinalPositions = crgRrhdLongitudinalPositions(data, options.NumSamples);
lateralPositions = crgRrhdSelectedVGrid(data, options.LaneVLimits);
centerPositions = (lateralPositions(1:end-1) + lateralPositions(2:end))/2;

[boundaries, data] = crgRrhdEvaluatePolylines(data, longitudinalPositions, ...
    lateralPositions, options.EvalChunkSize);
[centerLines, data] = crgRrhdEvaluatePolylines(data, longitudinalPositions, ...
    centerPositions, options.EvalChunkSize);

geometry.Mode = "LateralStrips";
geometry.Boundaries = boundaries;
geometry.CenterLines = centerLines;
geometry.LongitudinalPositions = longitudinalPositions;
geometry.LateralPositions = lateralPositions;
geometry.LaneVLimits = [lateralPositions(1) lateralPositions(end)];
geometry.CenterV = centerPositions;
end

function longitudinalPositions = crgRrhdLongitudinalPositions(data, sampleCount)
if sampleCount == 0
    sampleCount = size(data.z, 1);
end
if sampleCount < 2
    error('CRG:rrhdError', 'NumSamples must be at least 2')
end
longitudinalPositions = linspace(data.head.ubeg, data.head.uend, sampleCount).';
end

function lateralPositions = crgRrhdSelectedVGrid(data, laneVLimits)
lateralPositions = crgRrhdFullVGrid(data);
lateralLimits = crgRrhdLaneVLimits(data, laneVLimits);
selected = lateralPositions >= min(lateralLimits) & lateralPositions <= max(lateralLimits);
lateralPositions = lateralPositions(selected);
if numel(lateralPositions) < 2
    error('CRG:rrhdError', 'LateralStrips mode requires at least two CRG lateral grid columns')
end
end

function lateralPositions = crgRrhdFullVGrid(data)
columnCount = size(data.z, 2);
if isfield(data.head, 'vinc') && data.head.vinc > 0
    lateralPositions = linspace(data.head.vmin, data.head.vmax, columnCount);
elseif isfield(data, 'v') && isscalar(data.v)
    lateralPositions = linspace(-double(data.v), double(data.v), columnCount);
elseif isfield(data, 'v') && numel(data.v) == 2
    lateralPositions = linspace(double(data.v(1)), double(data.v(2)), columnCount);
elseif isfield(data, 'v') && numel(data.v) == columnCount
    lateralPositions = double(reshape(data.v, 1, []));
else
    error('CRG:rrhdError', 'Unable to determine OpenCRG lateral grid positions')
end
end

function lateralLimits = crgRrhdLaneVLimits(data, laneVLimits)
if any(isnan(laneVLimits))
    lateralLimits = [data.head.vmin data.head.vmax];
else
    lateralLimits = laneVLimits;
end

if lateralLimits(1) == lateralLimits(2)
    error('CRG:rrhdError', 'LaneVLimits must span a nonzero lane width')
end
if min(lateralLimits) < data.head.vmin || max(lateralLimits) > data.head.vmax
    error('CRG:rrhdError', 'LaneVLimits must lie inside the OpenCRG lateral range')
end
end

function centerOffset = crgRrhdCenterV(lateralLimits)
if min(lateralLimits) <= 0 && max(lateralLimits) >= 0
    centerOffset = 0;
else
    centerOffset = mean(lateralLimits);
end
end

function [polylines, data] = crgRrhdEvaluatePolylines(data, longitudinalPositions, lateralPositions, chunkSize)
rowCount = numel(longitudinalPositions);
columnCount = numel(lateralPositions);
chunkColumns = max(1, floor(chunkSize/rowCount));
polylines = cell(1, columnCount);

for startColumn = 1:chunkColumns:columnCount
    endColumn = min(columnCount, startColumn + chunkColumns - 1);
    columnRange = startColumn:endColumn;
    [uGrid, vGrid] = ndgrid(longitudinalPositions, lateralPositions(columnRange));
    uvPoints = [uGrid(:) vGrid(:)];
    [xyPoints, data] = crg_eval_uv2xy(data, uvPoints);
    [zPoints, data] = crg_eval_uv2z(data, uvPoints);
    points = reshape([xyPoints zPoints], rowCount, numel(columnRange), 3);
    for localColumn = 1:numel(columnRange)
        polylines{columnRange(localColumn)} = crgRrhdCleanGeometry(squeeze(points(:, localColumn, :)));
    end
end
end

function geometry = crgRrhdCleanGeometry(geometry)
finiteRows = all(isfinite(geometry), 2);
geometry = geometry(finiteRows, :);
if size(geometry, 1) > 1
    spacing = vecnorm(diff(geometry(:, 1:2), 1, 1), 2, 2);
    keepRows = [true; spacing > eps(max(abs(geometry(:))))];
    geometry = geometry(keepRows, :);
end
if size(geometry, 1) < 2
    error('CRG:rrhdError', 'RRHD geometry requires at least two finite points')
end
end

function rrMap = crgRrhdMap(geometry, data, options)
rrMap = roadrunnerHDMap;

switch geometry.Mode
    case "SingleLane"
        rrMap = crgRrhdSingleLaneMap(rrMap, geometry, options);
    case "LateralStrips"
        rrMap = crgRrhdStripMap(rrMap, geometry, options);
    otherwise
        error('CRG:rrhdError', 'Unsupported RRHD geometry mode: %s', geometry.Mode)
end

geoReference = crgRrhdGeoReference(data, options.GeoReference);
if ~isempty(geoReference)
    rrMap.GeoReference = geoReference;
end
end

function rrMap = crgRrhdSingleLaneMap(rrMap, geometry, options)
leftBoundary = roadrunner.hdmap.LaneBoundary;
leftBoundary.ID = options.LeftBoundaryID;
leftBoundary.Geometry = geometry.LeftBoundary;

rightBoundary = roadrunner.hdmap.LaneBoundary;
rightBoundary.ID = options.RightBoundaryID;
rightBoundary.Geometry = geometry.RightBoundary;

if options.AddEdgeMarkings && ~crgRrhdIsClosed(geometry.CenterLine)
    laneMarking = crgRrhdLaneMarking(options.MarkingID, options.MarkingAsset);
    leftBoundary.ParametricAttributes = crgRrhdMarkingAttribution(options.MarkingID);
    rightBoundary.ParametricAttributes = crgRrhdMarkingAttribution(options.MarkingID);
    rrMap.LaneMarkings = laneMarking;
end

lane = roadrunner.hdmap.Lane;
lane.ID = options.LaneID;
lane.Geometry = geometry.CenterLine;
lane.TravelDirection = options.TravelDirection;
lane.LaneType = options.LaneType;
lane.LeftLaneBoundary = crgRrhdAlignedReference(options.LeftBoundaryID);
lane.RightLaneBoundary = crgRrhdAlignedReference(options.RightBoundaryID);

laneBoundaries(1, 1) = leftBoundary;
laneBoundaries(2, 1) = rightBoundary;
rrMap.LaneBoundaries = laneBoundaries;
rrMap.Lanes = lane;
end

function rrMap = crgRrhdStripMap(rrMap, geometry, options)
boundaryCount = numel(geometry.Boundaries);
laneCount = numel(geometry.CenterLines);
boundaryIds = "StripBoundary_" + compose("%03d", 1:boundaryCount);
laneIds = "StripLane_" + compose("%03d", 1:laneCount);
laneBoundaries(boundaryCount, 1) = roadrunner.hdmap.LaneBoundary;
lanes(laneCount, 1) = roadrunner.hdmap.Lane;
isClosed = crgRrhdIsClosed(geometry.CenterLines{1});

for boundaryIndex = 1:boundaryCount
    laneBoundaries(boundaryIndex).ID = boundaryIds(boundaryIndex);
    laneBoundaries(boundaryIndex).Geometry = geometry.Boundaries{boundaryIndex};
end

markedBoundaryIndices = crgRrhdMarkedBoundaryIndices(boundaryCount, options, isClosed);
if ~isempty(markedBoundaryIndices)
    rrMap.LaneMarkings = crgRrhdLaneMarking(options.MarkingID, options.MarkingAsset);
    for boundaryIndex = markedBoundaryIndices
        laneBoundaries(boundaryIndex).ParametricAttributes = crgRrhdMarkingAttribution(options.MarkingID);
    end
end

for laneIndex = 1:laneCount
    lanes(laneIndex).ID = laneIds(laneIndex);
    lanes(laneIndex).Geometry = geometry.CenterLines{laneIndex};
    lanes(laneIndex).TravelDirection = options.TravelDirection;
    lanes(laneIndex).LaneType = options.StripLaneType;
    lanes(laneIndex).LeftLaneBoundary = crgRrhdAlignedReference(boundaryIds(laneIndex + 1));
    lanes(laneIndex).RightLaneBoundary = crgRrhdAlignedReference(boundaryIds(laneIndex));
end

rrMap.LaneBoundaries = laneBoundaries;
rrMap.Lanes = lanes;
end

function markedBoundaryIndices = crgRrhdMarkedBoundaryIndices(boundaryCount, options, isClosed)
if ~options.AddEdgeMarkings || isClosed || options.StripBoundaryMarkings == "None"
    markedBoundaryIndices = zeros(1, 0);
    return
end

switch options.StripBoundaryMarkings
    case "OuterOnly"
        markedBoundaryIndices = unique([1 boundaryCount]);
    case "All"
        markedBoundaryIndices = 1:boundaryCount;
    otherwise
        markedBoundaryIndices = zeros(1, 0);
end
end

function alignedReference = crgRrhdAlignedReference(referenceId)
reference = roadrunner.hdmap.Reference;
reference.ID = referenceId;
alignedReference = roadrunner.hdmap.AlignedReference;
alignedReference.Reference = reference;
alignedReference.Alignment = "Forward";
end

function laneMarking = crgRrhdLaneMarking(markingId, markingAsset)
laneMarking = roadrunner.hdmap.LaneMarking;
laneMarking.ID = markingId;
relativeAssetPath = roadrunner.hdmap.RelativeAssetPath;
relativeAssetPath.AssetPath = markingAsset;
laneMarking.AssetPath = relativeAssetPath;
end

function attribution = crgRrhdMarkingAttribution(markingId)
reference = roadrunner.hdmap.Reference;
reference.ID = markingId;
markingReference = roadrunner.hdmap.MarkingReference;
markingReference.MarkingID = reference;
markingReference.FlipLaterally = false;
attribution = roadrunner.hdmap.ParametricAttribution;
attribution.Span = [0 1];
attribution.MarkingReference = markingReference;
end

function geoReference = crgRrhdGeoReference(data, geoReference)
if isempty(geoReference) && isfield(data.head, 'nbeg') && isfield(data.head, 'ebeg')
    geoReference = [data.head.nbeg data.head.ebeg];
end

if ~isempty(geoReference)
    geoReference = reshape(double(geoReference), 1, []);
    if numel(geoReference) ~= 2 || any(~isfinite(geoReference)) || ...
            abs(geoReference(1)) > 90 || abs(geoReference(2)) > 180
        error('CRG:rrhdError', 'GeoReference must be [latitude longitude] in degrees')
    end
end
end

function isClosed = crgRrhdIsClosed(centerLine)
roadLength = sum(vecnorm(diff(centerLine(:, 1:2), 1, 1), 2, 2));
closingDistance = norm(centerLine(1, 1:2) - centerLine(end, 1:2));
isClosed = closingDistance <= max(1e-6, 1e-9*roadLength);
end

function crgRrhdValidate(rrMap)
if numel(rrMap.Lanes) < 1
    error('CRG:rrhdError', 'RRHD export requires at least one lane')
end
if numel(rrMap.LaneBoundaries) < 2
    error('CRG:rrhdError', 'RRHD export requires at least two lane boundaries')
end

for laneIndex = 1:numel(rrMap.Lanes)
    crgRrhdValidateGeometry(rrMap.Lanes(laneIndex).Geometry, "lane");
end
for boundaryIndex = 1:numel(rrMap.LaneBoundaries)
    crgRrhdValidateGeometry(rrMap.LaneBoundaries(boundaryIndex).Geometry, "lane boundary");
end

boundaryIds = string({rrMap.LaneBoundaries.ID});
for laneIndex = 1:numel(rrMap.Lanes)
    lane = rrMap.Lanes(laneIndex);
    leftIndex = crgRrhdBoundaryIndex(boundaryIds, string(lane.LeftLaneBoundary.Reference.ID));
    rightIndex = crgRrhdBoundaryIndex(boundaryIds, string(lane.RightLaneBoundary.Reference.ID));
    crgRrhdValidateLeftBoundary(lane.Geometry, rrMap.LaneBoundaries(leftIndex).Geometry);
    if leftIndex == rightIndex
        error('CRG:rrhdError', 'Lane %s references the same left and right boundary', lane.ID)
    end
end
end

function boundaryIndex = crgRrhdBoundaryIndex(boundaryIds, boundaryId)
boundaryIndex = find(boundaryIds == boundaryId, 1);
if isempty(boundaryIndex)
    error('CRG:rrhdError', 'Lane boundary reference %s does not resolve to an exported boundary', boundaryId)
end
end

function crgRrhdValidateGeometry(geometry, label)
if size(geometry, 2) ~= 3
    error('CRG:rrhdError', 'RRHD %s geometry must be Nx3', label)
end
if size(geometry, 1) < 2 || any(~isfinite(geometry), "all")
    error('CRG:rrhdError', 'RRHD %s geometry must contain at least two finite points', label)
end
end

function crgRrhdValidateLeftBoundary(centerLine, leftBoundary)
interiorCount = max(1, size(centerLine, 1)-2);
sampleCount = min(5, interiorCount);
sampleIndices = unique(round(linspace(2, max(2, size(centerLine, 1)-1), sampleCount)));
validSamples = 0;
leftSideSamples = 0;

for sampleIndex = sampleIndices
    beforeIndex = max(1, sampleIndex-1);
    afterIndex = min(size(centerLine, 1), sampleIndex+1);
    tangent = centerLine(afterIndex, 1:2) - centerLine(beforeIndex, 1:2);
    tangentLength = norm(tangent);
    if tangentLength == 0
        continue
    end
    leftNormal = [-tangent(2) tangent(1)]/tangentLength;
    distances = vecnorm(leftBoundary(:, 1:2) - centerLine(sampleIndex, 1:2), 2, 2);
    [~, closestIndex] = min(distances);
    validSamples = validSamples + 1;
    if dot(leftBoundary(closestIndex, 1:2) - centerLine(sampleIndex, 1:2), leftNormal) >= 0
        leftSideSamples = leftSideSamples + 1;
    end
end

if validSamples > 0 && leftSideSamples < ceil(validSamples/2)
    error('CRG:rrhdError', 'Left lane boundary is not spatially left of the lane centerline')
end
end
