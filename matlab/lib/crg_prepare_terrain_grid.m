function [prepared, metadata] = crg_prepare_terrain_grid(terrain, options)
%CRG_PREPARE_TERRAIN_GRID Validate terrain lookup data and precompute normals.

arguments
    terrain (1, 1) struct
    options.DefaultFriction (1, 1) double = 0.7
    options.DefaultMaterialId (1, 1) double {mustBeInteger, mustBePositive} = 2
    options.DefaultRoughness (1, 1) double = 0.0
    options.DefaultWetness (1, 1) double = 0.0
    options.DefaultTemperatureC (1, 1) double = 25.0
    options.DefaultRollingResistance (1, 1) double {mustBeNonnegative} = 0.015
end

localRequireFields(terrain, ["x", "y", "z"]);
x = double(terrain.x(:));
y = double(terrain.y(:));
z = double(terrain.z);
if numel(x) < 2 || numel(y) < 2 || ~isequal(size(z), [numel(x), numel(y)])
    error("CRG:terrainGridError", "Terrain z must have size [numel(x), numel(y)] with at least two points per axis.")
end
if any(~isfinite(x)) || any(~isfinite(y)) || any(~isfinite(z), "all") || any(diff(x) <= 0) || any(diff(y) <= 0)
    error("CRG:terrainGridError", "Terrain axes must be strictly increasing and terrain z must be finite.")
end

defaults = struct( ...
    "Friction", options.DefaultFriction, ...
    "MaterialId", options.DefaultMaterialId, ...
    "Roughness", options.DefaultRoughness, ...
    "Wetness", options.DefaultWetness, ...
    "TemperatureC", options.DefaultTemperatureC, ...
    "RollingResistance", options.DefaultRollingResistance);
prepared = struct( ...
    "x", x, ...
    "y", y, ...
    "z", z, ...
    "friction", localOptionalGrid(terrain, "friction", z, defaults.Friction), ...
    "materialId", localOptionalGrid(terrain, "materialId", z, defaults.MaterialId), ...
    "roughness", localOptionalGrid(terrain, "roughness", z, defaults.Roughness), ...
    "wetness", localOptionalGrid(terrain, "wetness", z, defaults.Wetness), ...
    "temperatureC", localOptionalGrid(terrain, "temperatureC", z, defaults.TemperatureC), ...
    "rollingResistance", localOptionalGrid(terrain, "rollingResistance", z, defaults.RollingResistance), ...
    "defaults", defaults);

normalFieldNames = ["normalX", "normalY", "normalZ"];
providedNormals = isfield(terrain, normalFieldNames);
if any(providedNormals) && ~all(providedNormals)
    error("CRG:terrainGridError", "Provide all terrain normal components or none of them.")
end
if all(providedNormals)
    normalX = localRequiredGrid(terrain.normalX, z, "normalX");
    normalY = localRequiredGrid(terrain.normalY, z, "normalY");
    normalZ = localRequiredGrid(terrain.normalZ, z, "normalZ");
else
    [dzDx, dzDy] = gradient(z, x, y);
    normalX = -dzDx;
    normalY = -dzDy;
    normalZ = ones(size(z));
end
[prepared.normalX, prepared.normalY, prepared.normalZ] = localNormalizeNormals(normalX, normalY, normalZ);
metadata = struct( ...
    "GridSize", size(z), ...
    "XRange", [x(1) x(end)], ...
    "YRange", [y(1) y(end)], ...
    "NormalsProvided", all(providedNormals), ...
    "Defaults", defaults);
end

function localRequireFields(value, fieldNames)
for fieldIndex = 1:numel(fieldNames)
    if ~isfield(value, fieldNames(fieldIndex))
        error("CRG:terrainGridError", "Terrain input is missing required field: %s", fieldNames(fieldIndex))
    end
end
end

function grid = localOptionalGrid(terrain, fieldName, referenceGrid, defaultValue)
if isfield(terrain, fieldName)
    grid = localRequiredGrid(terrain.(fieldName), referenceGrid, fieldName);
else
    grid = defaultValue*ones(size(referenceGrid));
end
end

function grid = localRequiredGrid(value, referenceGrid, fieldName)
grid = double(value);
if ~isequal(size(grid), size(referenceGrid)) || any(~isfinite(grid), "all")
    error("CRG:terrainGridError", "Terrain field %s must be finite and match terrain z size.", fieldName)
end
end

function [normalX, normalY, normalZ] = localNormalizeNormals(normalX, normalY, normalZ)
lengths = sqrt(normalX.^2 + normalY.^2 + normalZ.^2);
if any(~isfinite(lengths), "all") || any(lengths <= eps, "all")
    error("CRG:terrainGridError", "Terrain normals must be finite and nonzero.")
end
normalX = normalX./lengths;
normalY = normalY./lengths;
normalZ = normalZ./lengths;
downward = normalZ < 0;
normalX(downward) = -normalX(downward);
normalY(downward) = -normalY(downward);
normalZ(downward) = -normalZ(downward);
end
