function surface = crg_surface_bundle_terrain_lookup(x, y, bundle, terrain)
%CRG_SURFACE_BUNDLE_TERRAIN_LOOKUP Evaluate a bundle and terrain blend.

surface = localDefaultSurface(bundle);
if ~isfinite(x) || ~isfinite(y)
    return
end

[uv, roadData] = crg_eval_xy2uv(bundle.RoadData, [x y]);
uValue = uv(1);
vValue = uv(2);
isOnRoad = uValue >= roadData.head.ubeg && uValue <= roadData.head.uend && ...
    vValue >= roadData.head.vmin && vValue <= roadData.head.vmax;

if isOnRoad
    surface = localRoadSurface(bundle, roadData, uValue, vValue);
    surface.RoadWeight = 1.0;
    surface.DistanceToRoad = 0.0;
    surface.Status = "road";
    return
end

terrainSurface = localTerrainSurface(x, y, terrain);
if ~terrainSurface.IsValid
    return
end

[boundaryU, boundaryV, boundaryDistance] = localNearestBoundary(x, y, bundle.Boundary);
roadSurface = localRoadSurface(bundle, roadData, boundaryU, boundaryV);
if boundaryDistance > bundle.BlendWidth
    surface = terrainSurface;
    surface.Status = "terrain";
    surface.DistanceToRoad = boundaryDistance;
    return
end

roadWeight = 1.0 - boundaryDistance/bundle.BlendWidth;
surface = localBlendSurface(roadSurface, terrainSurface, roadWeight);
surface.Status = "blend";
surface.RoadWeight = roadWeight;
surface.DistanceToRoad = boundaryDistance;
end

function surface = localDefaultSurface(bundle)
defaults = bundle.Defaults.OffRoad;
surface = struct( ...
    "Height", NaN, ...
    "NormalX", 0.0, ...
    "NormalY", 0.0, ...
    "NormalZ", 1.0, ...
    "Friction", double(defaults.Friction), ...
    "MaterialId", double(defaults.MaterialId), ...
    "Roughness", double(defaults.Roughness), ...
    "Wetness", double(defaults.Wetness), ...
    "TemperatureC", double(defaults.TemperatureC), ...
    "RollingResistance", double(defaults.RollingResistance), ...
    "RoadWeight", 0.0, ...
    "DistanceToRoad", Inf, ...
    "Status", "invalid", ...
    "IsValid", false);
end

function surface = localRoadSurface(bundle, roadData, uValue, vValue)
[height, ~] = crg_eval_uv2z(roadData, [uValue vValue]);
surface = struct( ...
    "Height", double(height), ...
    "NormalX", localInterpolateRoadGrid(bundle, bundle.normalX, uValue, vValue, "linear"), ...
    "NormalY", localInterpolateRoadGrid(bundle, bundle.normalY, uValue, vValue, "linear"), ...
    "NormalZ", localInterpolateRoadGrid(bundle, bundle.normalZ, uValue, vValue, "linear"), ...
    "Friction", localInterpolateRoadGrid(bundle, bundle.friction, uValue, vValue, "linear"), ...
    "MaterialId", localInterpolateRoadGrid(bundle, bundle.materialId, uValue, vValue, "nearest"), ...
    "Roughness", localInterpolateRoadGrid(bundle, bundle.roughness, uValue, vValue, "linear"), ...
    "Wetness", localInterpolateRoadGrid(bundle, bundle.wetness, uValue, vValue, "linear"), ...
    "TemperatureC", localInterpolateRoadGrid(bundle, bundle.temperatureC, uValue, vValue, "linear"), ...
    "RollingResistance", localInterpolateRoadGrid(bundle, bundle.rollingResistance, uValue, vValue, "linear"), ...
    "RoadWeight", 1.0, ...
    "DistanceToRoad", 0.0, ...
    "Status", "road", ...
    "IsValid", true);
[surface.NormalX, surface.NormalY, surface.NormalZ] = ...
    localNormalizeVector(surface.NormalX, surface.NormalY, surface.NormalZ);
end

function surface = localTerrainSurface(xValue, yValue, terrain)
surface = struct( ...
    "Height", NaN, ...
    "NormalX", 0.0, ...
    "NormalY", 0.0, ...
    "NormalZ", 1.0, ...
    "Friction", terrain.defaults.Friction, ...
    "MaterialId", terrain.defaults.MaterialId, ...
    "Roughness", terrain.defaults.Roughness, ...
    "Wetness", terrain.defaults.Wetness, ...
    "TemperatureC", terrain.defaults.TemperatureC, ...
    "RollingResistance", terrain.defaults.RollingResistance, ...
    "RoadWeight", 0.0, ...
    "DistanceToRoad", Inf, ...
    "Status", "terrain", ...
    "IsValid", false);
if xValue < terrain.x(1) || xValue > terrain.x(end) || yValue < terrain.y(1) || yValue > terrain.y(end)
    return
end

surface.Height = localInterpolateTerrainGrid(terrain, terrain.z, xValue, yValue, "linear");
surface.NormalX = localInterpolateTerrainGrid(terrain, terrain.normalX, xValue, yValue, "linear");
surface.NormalY = localInterpolateTerrainGrid(terrain, terrain.normalY, xValue, yValue, "linear");
surface.NormalZ = localInterpolateTerrainGrid(terrain, terrain.normalZ, xValue, yValue, "linear");
surface.Friction = localInterpolateTerrainGrid(terrain, terrain.friction, xValue, yValue, "linear");
surface.MaterialId = localInterpolateTerrainGrid(terrain, terrain.materialId, xValue, yValue, "nearest");
surface.Roughness = localInterpolateTerrainGrid(terrain, terrain.roughness, xValue, yValue, "linear");
surface.Wetness = localInterpolateTerrainGrid(terrain, terrain.wetness, xValue, yValue, "linear");
surface.TemperatureC = localInterpolateTerrainGrid(terrain, terrain.temperatureC, xValue, yValue, "linear");
surface.RollingResistance = localInterpolateTerrainGrid(terrain, terrain.rollingResistance, xValue, yValue, "linear");
[surface.NormalX, surface.NormalY, surface.NormalZ] = ...
    localNormalizeVector(surface.NormalX, surface.NormalY, surface.NormalZ);
surface.IsValid = isfinite(surface.Height);
end

function value = localInterpolateRoadGrid(bundle, grid, uValue, vValue, method)
value = interp2(double(bundle.v(:)), double(bundle.u(:)), double(grid), vValue, uValue, method, NaN);
end

function value = localInterpolateTerrainGrid(terrain, grid, xValue, yValue, method)
value = interp2(terrain.y(:), terrain.x(:), grid, yValue, xValue, method, NaN);
end

function [uValue, vValue, distance] = localNearestBoundary(xValue, yValue, boundary)
segmentX = boundary.X2 - boundary.X1;
segmentY = boundary.Y2 - boundary.Y1;
pointX = xValue - boundary.X1;
pointY = yValue - boundary.Y1;
segmentLengthSquared = segmentX.^2 + segmentY.^2;
projection = (pointX.*segmentX + pointY.*segmentY)./max(segmentLengthSquared, eps);
projection = min(max(projection, 0.0), 1.0);
closestX = boundary.X1 + projection.*segmentX;
closestY = boundary.Y1 + projection.*segmentY;
distanceSquared = (xValue - closestX).^2 + (yValue - closestY).^2;
[minimumDistanceSquared, segmentIndex] = min(distanceSquared);
uValue = boundary.U1(segmentIndex) + projection(segmentIndex)*(boundary.U2(segmentIndex) - boundary.U1(segmentIndex));
vValue = boundary.V1(segmentIndex) + projection(segmentIndex)*(boundary.V2(segmentIndex) - boundary.V1(segmentIndex));
distance = sqrt(minimumDistanceSquared);
end

function surface = localBlendSurface(roadSurface, terrainSurface, roadWeight)
terrainWeight = 1.0 - roadWeight;
surface = roadSurface;
surface.Height = roadWeight*roadSurface.Height + terrainWeight*terrainSurface.Height;
surface.NormalX = roadWeight*roadSurface.NormalX + terrainWeight*terrainSurface.NormalX;
surface.NormalY = roadWeight*roadSurface.NormalY + terrainWeight*terrainSurface.NormalY;
surface.NormalZ = roadWeight*roadSurface.NormalZ + terrainWeight*terrainSurface.NormalZ;
[surface.NormalX, surface.NormalY, surface.NormalZ] = ...
    localNormalizeVector(surface.NormalX, surface.NormalY, surface.NormalZ);
surface.Friction = roadWeight*roadSurface.Friction + terrainWeight*terrainSurface.Friction;
surface.Roughness = roadWeight*roadSurface.Roughness + terrainWeight*terrainSurface.Roughness;
surface.Wetness = roadWeight*roadSurface.Wetness + terrainWeight*terrainSurface.Wetness;
surface.TemperatureC = roadWeight*roadSurface.TemperatureC + terrainWeight*terrainSurface.TemperatureC;
surface.RollingResistance = roadWeight*roadSurface.RollingResistance + terrainWeight*terrainSurface.RollingResistance;
if roadWeight >= 0.5
    surface.MaterialId = roadSurface.MaterialId;
else
    surface.MaterialId = terrainSurface.MaterialId;
end
surface.IsValid = roadSurface.IsValid && terrainSurface.IsValid;
end

function [normalX, normalY, normalZ] = localNormalizeVector(normalX, normalY, normalZ)
lengthValue = sqrt(normalX^2 + normalY^2 + normalZ^2);
if ~isfinite(lengthValue) || lengthValue <= eps
    normalX = 0.0;
    normalY = 0.0;
    normalZ = 1.0;
    return
end
normalX = normalX/lengthValue;
normalY = normalY/lengthValue;
normalZ = normalZ/lengthValue;
if normalZ < 0.0
    normalX = -normalX;
    normalY = -normalY;
    normalZ = -normalZ;
end
end
