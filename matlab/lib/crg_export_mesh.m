function [mesh, data] = crg_export_mesh(source, options)
%CRG_EXPORT_MESH Export OpenCRG data as a triangulated road mesh.

arguments
    source
    options.NumLongitudinalSamples (1, 1) double = NaN
    options.NumLateralSamples (1, 1) double = NaN
    options.LaneVLimits (1, 2) double = [NaN NaN]
    options.PhysicsMesh (1, 1) logical = false
    options.Thickness (1, 1) double = 0.05
    options.AddSkirts (1, 1) logical = true
    options.MaterialMode (1, 1) string = "Elevation"
    options.OutputClass (1, 1) string = "double"
    options.EvalChunkSize (1, 1) double = 100000
end

options = crgMeshValidateOptions(options);
[data, sourceFile] = crgMeshReadSource(source);
[uValues, vValues] = crgMeshSampleAxes(data, options);
[vertices, valueData, data] = crgMeshEvaluateSurface(data, uValues, vValues, options);

topFaces = crgMeshGridFaces(numel(uValues), numel(vValues));
if options.PhysicsMesh
    [vertices, faces] = crgMeshAddPhysicsVolume(vertices, topFaces, numel(uValues), ...
        numel(vValues), options);
else
    faces = topFaces;
end

normals = crgMeshVertexNormals(vertices, faces);
uvCoordinates = crgMeshUVCoordinates(uValues, vValues, options.PhysicsMesh);
vertexColor = crgMeshVertexColor(valueData, options.MaterialMode, options.PhysicsMesh);
mesh = crgMeshStruct(vertices, faces, normals, uvCoordinates, vertexColor, ...
    sourceFile, uValues, vValues, options);
end

function options = crgMeshValidateOptions(options)
options.OutputClass = string(validatestring(options.OutputClass, ["double", "single"]));
options.MaterialMode = string(validatestring(options.MaterialMode, ["Elevation", "Friction", "None"]));
if options.Thickness <= 0
    error("CRG:meshError", "Thickness must be positive.")
end
if options.EvalChunkSize < 1
    error("CRG:meshError", "EvalChunkSize must be positive.")
end
end

function [data, sourceFile] = crgMeshReadSource(source)
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
    if ~isfield(data, "ok")
        error("CRG:meshError", "Check of DATA was not completely successful.")
    end
end
end

function [uValues, vValues] = crgMeshSampleAxes(data, options)
lookup = crg_export_lookup(data, Write=false, CreateSimulinkLookupTable=false);
uBase = double(lookup.Breakpoints1(:));
vBase = double(lookup.Breakpoints2(:));

if all(isfinite(options.LaneVLimits))
    vMin = max(min(options.LaneVLimits), min(vBase));
    vMax = min(max(options.LaneVLimits), max(vBase));
    if vMin >= vMax
        error("CRG:meshError", "LaneVLimits must overlap the CRG lateral range.")
    end
else
    vMin = min(vBase);
    vMax = max(vBase);
end

if isnan(options.NumLongitudinalSamples)
    uValues = uBase;
else
    uValues = linspace(min(uBase), max(uBase), max(2, round(options.NumLongitudinalSamples))).';
end

if isnan(options.NumLateralSamples)
    vValues = vBase(vBase >= vMin & vBase <= vMax);
    if numel(vValues) < 2
        vValues = linspace(vMin, vMax, 2).';
    end
else
    vValues = linspace(vMin, vMax, max(2, round(options.NumLateralSamples))).';
end
end

function [vertices, valueData, data] = crgMeshEvaluateSurface(data, uValues, vValues, options)
[uGrid, vGrid] = ndgrid(uValues, vValues);
pointCount = numel(uGrid);
points = [uGrid(:), vGrid(:)];
xyValues = zeros(pointCount, 2);
zValues = zeros(pointCount, 1);
chunkSize = max(1, round(options.EvalChunkSize));

for startIndex = 1:chunkSize:pointCount
    endIndex = min(pointCount, startIndex+chunkSize-1);
    chunk = points(startIndex:endIndex, :);
    [xyChunk, data] = crg_eval_uv2xy(data, chunk);
    [zChunk, data] = crg_eval_uv2z(data, chunk);
    xyValues(startIndex:endIndex, :) = xyChunk;
    zValues(startIndex:endIndex) = zChunk;
end

vertices = [xyValues, zValues];
valueData = zValues;
end

function faces = crgMeshGridFaces(rowCount, columnCount)
faceCount = 2*(rowCount-1)*(columnCount-1);
faces = zeros(faceCount, 3);
gridIndex = reshape(1:(rowCount*columnCount), rowCount, columnCount);
faceIndex = 1;

for columnIndex = 1:(columnCount-1)
    for rowIndex = 1:(rowCount-1)
        a = gridIndex(rowIndex, columnIndex);
        b = gridIndex(rowIndex+1, columnIndex);
        c = gridIndex(rowIndex, columnIndex+1);
        d = gridIndex(rowIndex+1, columnIndex+1);
        faces(faceIndex, :) = [a b c];
        faces(faceIndex+1, :) = [b d c];
        faceIndex = faceIndex + 2;
    end
end
end

function [vertices, faces] = crgMeshAddPhysicsVolume(topVertices, topFaces, rowCount, columnCount, options)
topCount = size(topVertices, 1);
bottomVertices = topVertices;
bottomVertices(:, 3) = bottomVertices(:, 3) - options.Thickness;
vertices = [topVertices; bottomVertices];
bottomFaces = fliplr(topFaces + topCount);
sideFaceCount = 0;
if options.AddSkirts
    sideFaceCount = 4*(rowCount + columnCount - 2);
end

faces = zeros(size(topFaces, 1) + size(bottomFaces, 1) + sideFaceCount, 3);
faces(1:size(topFaces, 1), :) = topFaces;
faces(size(topFaces, 1)+(1:size(bottomFaces, 1)), :) = bottomFaces;
faceIndex = size(topFaces, 1) + size(bottomFaces, 1) + 1;

if ~options.AddSkirts
    return
end

gridIndex = reshape(1:topCount, rowCount, columnCount);
for rowIndex = 1:(rowCount-1)
    [faces, faceIndex] = crgMeshAppendQuad(faces, faceIndex, ...
        gridIndex(rowIndex, 1), gridIndex(rowIndex+1, 1), topCount);
    [faces, faceIndex] = crgMeshAppendQuad(faces, faceIndex, ...
        gridIndex(rowIndex+1, columnCount), gridIndex(rowIndex, columnCount), topCount);
end
for columnIndex = 1:(columnCount-1)
    [faces, faceIndex] = crgMeshAppendQuad(faces, faceIndex, ...
        gridIndex(1, columnIndex+1), gridIndex(1, columnIndex), topCount);
    [faces, faceIndex] = crgMeshAppendQuad(faces, faceIndex, ...
        gridIndex(rowCount, columnIndex), gridIndex(rowCount, columnIndex+1), topCount);
end
end

function [faces, faceIndex] = crgMeshAppendQuad(faces, faceIndex, firstTop, secondTop, topCount)
firstBottom = firstTop + topCount;
secondBottom = secondTop + topCount;
faces(faceIndex, :) = [firstTop secondTop firstBottom];
faces(faceIndex+1, :) = [secondTop secondBottom firstBottom];
faceIndex = faceIndex + 2;
end

function normals = crgMeshVertexNormals(vertices, faces)
normals = zeros(size(vertices));
for faceIndex = 1:size(faces, 1)
    face = faces(faceIndex, :);
    edge1 = vertices(face(2), :) - vertices(face(1), :);
    edge2 = vertices(face(3), :) - vertices(face(1), :);
    faceNormal = cross(edge1, edge2);
    normalLength = norm(faceNormal);
    if normalLength > 0
        faceNormal = faceNormal / normalLength;
    end
    normals(face(1), :) = normals(face(1), :) + faceNormal;
    normals(face(2), :) = normals(face(2), :) + faceNormal;
    normals(face(3), :) = normals(face(3), :) + faceNormal;
end

normalLength = sqrt(sum(normals.^2, 2));
zeroNormals = normalLength == 0;
normalLength(zeroNormals) = 1;
normals = normals ./ normalLength;
normals(zeroNormals, :) = repmat([0 0 1], nnz(zeroNormals), 1);
end

function uvCoordinates = crgMeshUVCoordinates(uValues, vValues, hasBottom)
[uGrid, vGrid] = ndgrid(crgMeshNormalize(uValues), crgMeshNormalize(vValues));
uvCoordinates = [uGrid(:), vGrid(:)];
if hasBottom
    uvCoordinates = [uvCoordinates; uvCoordinates];
end
end

function values = crgMeshNormalize(values)
values = double(values(:));
valueRange = max(values) - min(values);
if valueRange == 0
    values = zeros(size(values));
else
    values = (values - min(values)) / valueRange;
end
end

function vertexColor = crgMeshVertexColor(valueData, materialMode, hasBottom)
if materialMode == "None"
    vertexColor = zeros(0, 3);
    return
end

colorValue = crgMeshNormalize(valueData);
vertexColor = [colorValue, 0.35 + 0.25*(1-colorValue), 1-colorValue];
if hasBottom
    vertexColor = [vertexColor; vertexColor];
end
end

function mesh = crgMeshStruct(vertices, faces, normals, uvCoordinates, vertexColor, ...
    sourceFile, uValues, vValues, options)
vertices = crgMeshCast(vertices, options.OutputClass);
normals = crgMeshCast(normals, options.OutputClass);
uvCoordinates = crgMeshCast(uvCoordinates, options.OutputClass);
vertexColor = crgMeshCast(vertexColor, options.OutputClass);

mesh = struct( ...
    "Vertices", vertices, ...
    "Faces", faces, ...
    "Normals", normals, ...
    "UV", uvCoordinates, ...
    "VertexColor", vertexColor, ...
    "Metadata", struct( ...
        "SourceFile", sourceFile, ...
        "Units", "m", ...
        "CoordinateFrame", "CRG local x/y/z", ...
        "PhysicsMesh", options.PhysicsMesh, ...
        "Thickness", options.Thickness, ...
        "AddSkirts", options.AddSkirts, ...
        "MaterialMode", options.MaterialMode, ...
        "GridSize", [numel(uValues) numel(vValues)], ...
        "SurfaceVertexCount", numel(uValues)*numel(vValues), ...
        "FaceCount", size(faces, 1)));
end

function value = crgMeshCast(value, outputClass)
switch outputClass
    case "double"
        value = double(value);
    case "single"
        value = single(value);
    otherwise
        error("CRG:meshError", "Unsupported output class: %s.", outputClass)
end
end
