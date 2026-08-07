function [rrMap, data, geometry] = crg_write_rrhd(source, rrhdFile, options)
%CRG_WRITE_RRHD Export OpenCRG road data as RoadRunner HD Map.
%   RRMAP = CRG_WRITE_RRHD(SOURCE, RRHDFILE) reads OpenCRG data from SOURCE
%   and writes a single-lane RoadRunner HD Map file to RRHDFILE.
%
%   [RRMAP, DATA, GEOMETRY] = CRG_WRITE_RRHD(___) also returns the checked
%   OpenCRG data and the exported lane and boundary geometries.
%
%   SOURCE can be a CRG file name or a DATA struct as defined in CRG_INTRO.
%
%   Name-value options:
%       NumSamples       Number of longitudinal samples. Default uses CRG rows.
%       LaneVLimits      [right left] lateral offsets. Default uses CRG limits.
%       CenterV          Lane-center lateral offset. Default is zero if inside.
%       GeoReference     [latitude longitude] in degrees.
%       AddEdgeMarkings  Add solid white markings to both lane boundaries.
%       Write            Write RRHDFILE. Set false to build RRMAP only.
%
%   Example:
%       crg_write_rrhd("road.crg", "road.rrhd", NumSamples=250)
%
%   See also CRG_READ, CRG_EVAL_UV2XY, CRG_EVAL_UV2Z.

arguments
    source
    rrhdFile {mustBeTextScalar} = ""
    options.NumSamples (1, 1) double {mustBeInteger, mustBeNonnegative} = 0
    options.LaneVLimits (1, 2) double = [NaN NaN]
    options.CenterV (1, 1) double = NaN
    options.GeoReference double = []
    options.LaneID (1, 1) string = "Lane1"
    options.LeftBoundaryID (1, 1) string = "Left"
    options.RightBoundaryID (1, 1) string = "Right"
    options.TravelDirection (1, 1) string = "Forward"
    options.LaneType (1, 1) string = "Driving"
    options.AddEdgeMarkings (1, 1) logical = true
    options.MarkingID (1, 1) string = "SolidWhite"
    options.MarkingAsset (1, 1) string = "Assets/Markings/SolidSingleWhite.rrlms"
    options.Write (1, 1) logical = true
end

[data, sourceFile] = crgRrhdReadSource(source);
rrhdFile = crgRrhdOutputFile(rrhdFile, sourceFile, options.Write);
[geometry, data] = crgRrhdGeometry(data, options.NumSamples, options.LaneVLimits, options.CenterV);
rrMap = crgRrhdMap(geometry, data, options);
crgRrhdValidate(rrMap);

if options.Write
    write(rrMap, rrhdFile);
end
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

function [geometry, data] = crgRrhdGeometry(data, sampleCount, laneVLimits, centerOffset)
if sampleCount == 0
    sampleCount = size(data.z, 1);
end
if sampleCount < 2
    error('CRG:rrhdError', 'NumSamples must be at least 2')
end

lateralLimits = crgRrhdLaneVLimits(data, laneVLimits);
if isnan(centerOffset)
    centerOffset = crgRrhdCenterV(lateralLimits);
end
if centerOffset < min(lateralLimits) || centerOffset > max(lateralLimits)
    error('CRG:rrhdError', 'CenterV must lie inside LaneVLimits')
end

longitudinalPositions = linspace(data.head.ubeg, data.head.uend, sampleCount).';
leftOffset = max(lateralLimits);
rightOffset = min(lateralLimits);

leftUv = [longitudinalPositions repmat(leftOffset, sampleCount, 1)];
centerUv = [longitudinalPositions repmat(centerOffset, sampleCount, 1)];
rightUv = [longitudinalPositions repmat(rightOffset, sampleCount, 1)];
allUv = [leftUv; centerUv; rightUv];

[allXy, data] = crg_eval_uv2xy(data, allUv);
[allZ, data] = crg_eval_uv2z(data, allUv);

leftRows = 1:sampleCount;
centerRows = sampleCount + leftRows;
rightRows = 2*sampleCount + leftRows;

geometry.LeftBoundary = crgRrhdCleanGeometry([allXy(leftRows, :) allZ(leftRows)]);
geometry.CenterLine = crgRrhdCleanGeometry([allXy(centerRows, :) allZ(centerRows)]);
geometry.RightBoundary = crgRrhdCleanGeometry([allXy(rightRows, :) allZ(rightRows)]);
geometry.LongitudinalPositions = longitudinalPositions;
geometry.LaneVLimits = [rightOffset leftOffset];
geometry.CenterV = centerOffset;
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

geoReference = crgRrhdGeoReference(data, options.GeoReference);
if ~isempty(geoReference)
    rrMap.GeoReference = geoReference;
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
if numel(rrMap.Lanes) ~= 1
    error('CRG:rrhdError', 'RRHD export currently supports exactly one lane')
end
if numel(rrMap.LaneBoundaries) ~= 2
    error('CRG:rrhdError', 'RRHD export requires exactly two lane boundaries')
end

lane = rrMap.Lanes(1);
crgRrhdValidateGeometry(lane.Geometry, "lane");
for boundaryIndex = 1:numel(rrMap.LaneBoundaries)
    crgRrhdValidateGeometry(rrMap.LaneBoundaries(boundaryIndex).Geometry, "lane boundary");
end

boundaryIds = string({rrMap.LaneBoundaries.ID});
leftId = string(lane.LeftLaneBoundary.Reference.ID);
rightId = string(lane.RightLaneBoundary.Reference.ID);
if ~any(boundaryIds == leftId) || ~any(boundaryIds == rightId)
    error('CRG:rrhdError', 'Lane boundary references must resolve to exported boundaries')
end

leftBoundary = rrMap.LaneBoundaries(find(boundaryIds == leftId, 1)).Geometry;
crgRrhdValidateLeftBoundary(lane.Geometry, leftBoundary);
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
