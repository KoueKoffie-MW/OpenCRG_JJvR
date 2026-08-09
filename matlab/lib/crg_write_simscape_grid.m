function [x, y, z, data] = crg_write_simscape_grid(source, matFile, options)
%CRG_WRITE_SIMSCAPE_GRID Export OpenCRG data for Simscape Grid Surface.
%   [X, Y, Z] = CRG_WRITE_SIMSCAPE_GRID(SOURCE) samples SOURCE and returns
%   grid variables for the Simscape Multibody Grid Surface block.
%
%   SOURCE can be a CRG file name or a DATA struct as defined in CRG_INTRO.
%   The returned X and Y vectors are regular local-coordinate grid vectors.
%   Z is a matrix with size [numel(X), numel(Y)].
%
%   CRG_WRITE_SIMSCAPE_GRID(SOURCE, MATFILE) saves variables named x, y,
%   and z to MATFILE for direct use in Grid Surface mask parameters.
%
%   Name-value options:
%       GridResolution          Regular x/y spacing in meters.
%       NumLongitudinalSamples  Longitudinal CRG samples. Default uses CRG rows.
%       NumLateralSamples       Lateral CRG samples. Default uses CRG columns.
%       LaneVLimits             [right left] lateral offsets. Default uses CRG limits.
%       InterpolationMethod     scatteredInterpolant interpolation method.
%       ExtrapolationMethod     scatteredInterpolant extrapolation method.
%       EvalChunkSize           Maximum UV points per evaluation chunk.
%       OutputClass             "double" or "single".
%       Write                   Save x, y, and z to MATFILE.
%
%   Example:
%       [x, y, z] = crg_write_simscape_grid("road.crg", GridResolution=0.5)
%
%   See also CRG_READ, CRG_EVAL_UV2XY, CRG_EVAL_UV2Z.

arguments
    source
    matFile {mustBeTextScalar} = ""
    options.GridResolution (1, 1) double {mustBePositive} = 0.5
    options.NumLongitudinalSamples (1, 1) double {mustBeInteger, mustBeNonnegative} = 0
    options.NumLateralSamples (1, 1) double {mustBeInteger, mustBeNonnegative} = 0
    options.LaneVLimits (1, 2) double = [NaN NaN]
    options.InterpolationMethod (1, 1) string = "linear"
    options.ExtrapolationMethod (1, 1) string = "nearest"
    options.EvalChunkSize (1, 1) double {mustBeInteger, mustBePositive} = 250000
    options.OutputClass (1, 1) string = "double"
    options.Write (1, 1) logical = true
end

options = crgSimscapeValidateOptions(options);
[data, sourceFile] = crgSimscapeReadSource(source);
matFile = crgSimscapeOutputFile(matFile, sourceFile, options.Write);

uValues = crgSimscapeLongitudinalValues(data, options.NumLongitudinalSamples);
vValues = crgSimscapeLateralValues(data, options.LaneVLimits, options.NumLateralSamples);
[surfaceX, surfaceY, surfaceZ, data] = crgSimscapeEvaluateSurface(data, uValues, vValues, options.EvalChunkSize);
[x, y, z] = crgSimscapeInterpolateGrid(surfaceX, surfaceY, surfaceZ, options);

if options.OutputClass == "single"
    x = single(x);
    y = single(y);
    z = single(z);
end

if options.Write
    save(matFile, "x", "y", "z");
end
end

function options = crgSimscapeValidateOptions(options)
options.InterpolationMethod = string(validatestring(options.InterpolationMethod, ...
    ["linear", "nearest", "natural"]));
options.ExtrapolationMethod = string(validatestring(options.ExtrapolationMethod, ...
    ["linear", "nearest", "none"]));
options.OutputClass = string(validatestring(options.OutputClass, ["double", "single"]));
end

function [data, sourceFile] = crgSimscapeReadSource(source)
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
        error('CRG:simscapeGridError', 'check of DATA was not completely successful')
    end
end
end

function matFile = crgSimscapeOutputFile(matFile, sourceFile, writeOutput)
matFile = string(matFile);
if matFile == "" && writeOutput
    if sourceFile == ""
        error('CRG:simscapeGridError', 'MATFILE is required when SOURCE is a data struct and Write is true')
    end
    [folder, name] = fileparts(sourceFile);
    matFile = fullfile(folder, name + "_SimscapeGrid.mat");
end

if matFile ~= ""
    [folder, name, extension] = fileparts(matFile);
    if extension == ""
        matFile = fullfile(folder, name + ".mat");
    end
end
end

function uValues = crgSimscapeLongitudinalValues(data, sampleCount)
if sampleCount == 0
    sampleCount = size(data.z, 1);
end
if sampleCount < 2
    error('CRG:simscapeGridError', 'NumLongitudinalSamples must be at least 2')
end
uValues = linspace(data.head.ubeg, data.head.uend, sampleCount).';
end

function vValues = crgSimscapeLateralValues(data, laneVLimits, sampleCount)
lateralLimits = crgSimscapeLateralLimits(data, laneVLimits);
if sampleCount > 0
    if sampleCount < 2
        error('CRG:simscapeGridError', 'NumLateralSamples must be at least 2')
    end
    vValues = linspace(lateralLimits(1), lateralLimits(2), sampleCount);
    return
end

vValues = crgSimscapeFullVGrid(data);
selected = vValues >= lateralLimits(1) & vValues <= lateralLimits(2);
vValues = vValues(selected);
tolerance = 10*eps(max(abs(lateralLimits)));

if isempty(vValues) || abs(vValues(1) - lateralLimits(1)) > tolerance
    vValues = [lateralLimits(1) vValues];
end
if abs(vValues(end) - lateralLimits(2)) > tolerance
    vValues(end+1) = lateralLimits(2);
end
if numel(vValues) < 2
    error('CRG:simscapeGridError', 'At least two lateral samples are required')
end
end

function lateralLimits = crgSimscapeLateralLimits(data, laneVLimits)
if any(isnan(laneVLimits))
    lateralLimits = [data.head.vmin data.head.vmax];
else
    lateralLimits = [min(laneVLimits) max(laneVLimits)];
end

if lateralLimits(1) == lateralLimits(2)
    error('CRG:simscapeGridError', 'LaneVLimits must span a nonzero lateral width')
end
if lateralLimits(1) < data.head.vmin || lateralLimits(2) > data.head.vmax
    error('CRG:simscapeGridError', 'LaneVLimits must lie inside the OpenCRG lateral range')
end
end

function vValues = crgSimscapeFullVGrid(data)
columnCount = size(data.z, 2);
if isfield(data.head, 'vinc') && data.head.vinc > 0
    vValues = linspace(data.head.vmin, data.head.vmax, columnCount);
elseif isfield(data, 'v') && isscalar(data.v)
    vValues = linspace(-double(data.v), double(data.v), columnCount);
elseif isfield(data, 'v') && numel(data.v) == 2
    vValues = linspace(double(data.v(1)), double(data.v(2)), columnCount);
elseif isfield(data, 'v') && numel(data.v) == columnCount
    vValues = double(reshape(data.v, 1, []));
else
    error('CRG:simscapeGridError', 'Unable to determine OpenCRG lateral grid positions')
end
end

function [surfaceX, surfaceY, surfaceZ, data] = crgSimscapeEvaluateSurface(data, uValues, vValues, chunkSize)
uCount = numel(uValues);
vCount = numel(vValues);
chunkColumns = max(1, floor(chunkSize/uCount));
surfaceX = zeros(uCount, vCount);
surfaceY = zeros(uCount, vCount);
surfaceZ = zeros(uCount, vCount);

for startColumn = 1:chunkColumns:vCount
    endColumn = min(vCount, startColumn + chunkColumns - 1);
    columnRange = startColumn:endColumn;
    [uGrid, vGrid] = ndgrid(uValues, vValues(columnRange));
    uvPoints = [uGrid(:) vGrid(:)];
    [xyPoints, data] = crg_eval_uv2xy(data, uvPoints);
    [zPoints, data] = crg_eval_uv2z(data, uvPoints);
    surfaceX(:, columnRange) = reshape(xyPoints(:, 1), uCount, numel(columnRange));
    surfaceY(:, columnRange) = reshape(xyPoints(:, 2), uCount, numel(columnRange));
    surfaceZ(:, columnRange) = reshape(zPoints, uCount, numel(columnRange));
end
end

function [x, y, z] = crgSimscapeInterpolateGrid(surfaceX, surfaceY, surfaceZ, options)
validPoints = isfinite(surfaceX) & isfinite(surfaceY) & isfinite(surfaceZ);
if nnz(validPoints) < 3
    error('CRG:simscapeGridError', 'At least three finite CRG surface points are required')
end

x = crgSimscapeRegularAxis(min(surfaceX(validPoints)), max(surfaceX(validPoints)), options.GridResolution);
y = crgSimscapeRegularAxis(min(surfaceY(validPoints)), max(surfaceY(validPoints)), options.GridResolution);
[queryX, queryY] = ndgrid(x, y);
interpolant = scatteredInterpolant(surfaceX(validPoints), surfaceY(validPoints), surfaceZ(validPoints), ...
    options.InterpolationMethod, options.ExtrapolationMethod);
z = interpolant(queryX, queryY);
end

function axisValues = crgSimscapeRegularAxis(minValue, maxValue, resolution)
if maxValue <= minValue
    error('CRG:simscapeGridError', 'Grid axis extent must be nonzero')
end

axisValues = minValue:resolution:maxValue;
if isempty(axisValues) || axisValues(end) < maxValue
    axisValues(end+1) = maxValue;
end
if numel(axisValues) < 2
    axisValues = [minValue maxValue];
end
axisValues = reshape(axisValues, 1, []);
end
