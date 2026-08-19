function [road, metadata] = crg_export_tire_plane_lookup(source, matFile, options)
%CRG_EXPORT_TIRE_PLANE_LOOKUP Export CRG-native tire-plane lookup data.
%   ROAD = CRG_EXPORT_TIRE_PLANE_LOOKUP(SOURCE) creates a compact numeric
%   ROAD struct for CRG_TIRE_PLANE_LOOKUP_STEP. The runtime keeps data in
%   CRG u/v coordinates to avoid large world x/y lookup grids.

arguments
    source
    matFile {mustBeTextScalar} = ""
    options.Precision (1, 1) string = "single"
    options.LocalSearchRadius (1, 1) double {mustBeInteger, mustBePositive} = 25
    options.CoarseSearchStride (1, 1) double {mustBeInteger, mustBePositive} = 25
    options.CoarseRefineRadius (1, 1) double {mustBeInteger, mustBePositive} = 50
    options.MaxLocalDistance (1, 1) double = Inf
    options.Write (1, 1) logical = true
end

precision = validatestring(options.Precision, ["single", "double"]);
[data, sourceFile] = localReadData(source);
numU = size(data.z, 1);
numV = size(data.z, 2);

u = localColumnVector(localUVector(data, numU));
v = localColumnVector(localVVector(data, numV));
xRef = localColumnVector(data.rx);
yRef = localColumnVector(data.ry);
phi = localColumnVector(localPhiVector(data, u));
slope = localColumnVector(localSlopeVector(data, numU));
bank = localColumnVector(localBankVector(data, numU));
coarseIndex = localCoarseIndex(numU, options.CoarseSearchStride);
maxLocalDistance = options.MaxLocalDistance;
if isinf(maxLocalDistance)
    maxLocalDistance = max(20.0, 4.0*max(abs([data.head.vmin, data.head.vmax])));
end

road = struct( ...
    "u", localCast(u, precision), ...
    "v", localCast(v, precision), ...
    "z", localCast(data.z, precision), ...
    "xRef", localCast(xRef, precision), ...
    "yRef", localCast(yRef, precision), ...
    "phi", localCast(phi, precision), ...
    "slope", localCast(slope, precision), ...
    "bank", localCast(bank, precision), ...
    "coarseIndex", coarseIndex, ...
    "numU", double(numU), ...
    "numV", double(numV), ...
    "uMin", double(u(1)), ...
    "uMax", double(u(end)), ...
    "uInc", double(data.head.uinc), ...
    "vMin", double(v(1)), ...
    "vMax", double(v(end)), ...
    "vInc", localRegularIncrement(v), ...
    "isVRegular", double(localIsRegular(v)), ...
    "zBeg", double(data.head.zbeg), ...
    "sBeg", double(data.head.sbeg), ...
    "localSearchRadius", double(options.LocalSearchRadius), ...
    "coarseRefineRadius", double(options.CoarseRefineRadius), ...
    "maxLocalDistance", double(maxLocalDistance));

metadata = struct( ...
    "SourceFile", sourceFile, ...
    "Precision", string(precision), ...
    "GridSize", [numU, numV], ...
    "ApproxBytes", localApproxBytes(road), ...
    "RuntimeFunction", "crg_tire_plane_lookup_step", ...
    "Inputs", ["x", "y", "pz_prev", "x_prev", "y_prev", "iu_prev", "road"], ...
    "Outputs", ["px", "py", "pz", "iu_curr", "qx", "qy", "qz"]);

if options.Write
    if matFile == ""
        if sourceFile == ""
            error("CRG:tirePlaneLookupError", ...
                "MATFILE is required when SOURCE does not provide a file name.")
        end
        [folder, name] = fileparts(sourceFile);
        matFile = fullfile(folder, name + "_TirePlaneLookup.mat");
    end
    save(matFile, "road", "metadata", "-v7.3");
end
end

function [data, sourceFile] = localReadData(source)
if isstruct(source)
    data = source;
    if isfield(data, "filenm")
        sourceFile = string(data.filenm);
    else
        sourceFile = "";
    end
else
    sourceFile = string(source);
    data = crg_read(sourceFile);
end

if ~isfield(data, "ok")
    data = crg_check(data);
end
end

function values = localUVector(data, numU)
if isfield(data, "u") && numel(data.u) == numU
    values = double(data.u(:));
else
    values = data.head.ubeg + (0:numU-1).'*data.head.uinc;
end
end

function values = localVVector(data, numV)
if isfield(data, "v") && numel(data.v) == numV
    values = double(data.v(:));
elseif isfield(data.head, "vinc") && data.head.vinc ~= 0
    values = data.head.vmin + (0:numV-1).'*data.head.vinc;
else
    values = linspace(data.head.vmin, data.head.vmax, numV).';
end
end

function values = localPhiVector(data, u)
if isfield(data, "p")
    values = crg_eval_u2phi(data, u(:).');
    values = values(:);
else
    values = repmat(double(data.head.pbeg), numel(u), 1);
end
end

function values = localSlopeVector(data, numU)
if isfield(data, "s")
    values = localExpandSegmentChannel(data.s, data.head.sbeg, data.head.send, numU);
else
    values = repmat(double(data.head.sbeg), numU, 1);
end
end

function values = localBankVector(data, numU)
if isfield(data, "b")
    channel = double(data.b(:));
    if isscalar(channel)
        values = repmat(channel, numU, 1);
    elseif numel(channel) == numU
        values = channel;
    else
        values = localExpandSegmentChannel(channel, data.head.bbeg, data.head.bend, numU);
    end
else
    values = repmat(double(data.head.bbeg), numU, 1);
end
end

function values = localExpandSegmentChannel(channel, firstValue, lastValue, numU)
channel = double(channel(:));
if isscalar(channel)
    values = repmat(channel, numU, 1);
elseif numel(channel) == numU - 1
    values = [channel; double(lastValue)];
    values(1) = double(firstValue);
else
    error("CRG:tirePlaneLookupError", "Unsupported CRG channel length for tire-plane lookup export.")
end
end

function values = localColumnVector(values)
values = values(:);
end

function values = localCast(values, precision)
if precision == "single"
    values = single(values);
else
    values = double(values);
end
end

function coarseIndex = localCoarseIndex(numU, stride)
coarseIndex = 1:stride:max(1, numU - 1);
if coarseIndex(end) ~= max(1, numU - 1)
    coarseIndex(end+1) = max(1, numU - 1);
end
coarseIndex = double(coarseIndex(:));
end

function tf = localIsRegular(values)
if numel(values) < 3
    tf = true;
else
    increments = diff(values);
    tf = max(abs(increments - increments(1))) <= max(1.0, abs(increments(1)))*1e-9;
end
end

function increment = localRegularIncrement(values)
if numel(values) > 1
    increment = double(values(2) - values(1));
else
    increment = 0.0;
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