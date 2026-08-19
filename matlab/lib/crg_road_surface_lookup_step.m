function [px, py, pz, iuCurr, qx, qy, qz, mu] = crg_road_surface_lookup_step( ...
    x, y, pzPrev, xPrev, yPrev, iuPrev, road) %#codegen
%CRG_ROAD_SURFACE_LOOKUP_STEP Evaluate road height, contact plane and friction.

coder.allowpcode('plain');

px = x;
py = y;
pz = pzPrev;
iuCurr = iuPrev;
qx = 0.0;
qy = 0.0;
qz = 0.0;
mu = 1.0;

if ~isfinite(x) || ~isfinite(y)
    return
end

[segmentIndex, projection, lateralDistance, isValidProjection] = localProjectToReference(x, y, iuPrev, road);
if ~isValidProjection
    return
end

uValue = localInterpolateU(segmentIndex, projection, road);
vValue = lateralDistance;
if ~localInsideUv(uValue, vValue, road)
    return
end

[uIndex, uFraction] = localFindUInterval(uValue, road);
[vIndex, vFraction] = localFindVInterval(vValue, road);
pzCandidate = localInterpolateElevation( ...
    uValue, vValue, uIndex, vIndex, uFraction, vFraction, road);
if ~isfinite(pzCandidate)
    return
end

phiValue = road.phi(uIndex);
if road.hasFriction ~= 0.0
    muCandidate = localInterpolateGridAt(road.friction, uIndex, vIndex, uFraction, vFraction);
    if isfinite(muCandidate)
        mu = double(muCandidate);
    end
end

if road.hasNormals ~= 0.0
    [qx, qy] = localAnglesFromNormal( ...
        uIndex, vIndex, uFraction, vFraction, phiValue, road);
else
    slopeValue = localInterpolateVectorAt(road.slope, uIndex, uFraction);
    bankValue = localInterpolateVectorAt(road.bank, uIndex, uFraction);
    qx = atan(double(bankValue));
    qy = -atan(double(slopeValue));
end

pz = pzCandidate;
iuCurr = double(segmentIndex);
qz = double(phiValue);

if ~isfinite(iuCurr)
    iuCurr = iuPrev;
end

if ~isfinite(xPrev) || ~isfinite(yPrev)
    return
end
end

function [segmentIndex, projection, lateralDistance, isValidProjection] = localProjectToReference(x, y, iuPrev, road)
numSegments = max(1, int32(road.numU) - 1);
startIndex = localPreviousIndex(iuPrev, numSegments);
radius = int32(road.localSearchRadius);
firstIndex = max(int32(1), startIndex - radius);
lastIndex = min(numSegments, startIndex + radius);

[segmentIndex, projection, lateralDistance, distanceSquared] = localSearchSegments(x, y, firstIndex, lastIndex, road);
maxLocalDistanceSquared = road.maxLocalDistance*road.maxLocalDistance;
if (~isfinite(iuPrev)) || iuPrev < 1.0 || iuPrev > double(numSegments) || ...
        distanceSquared > maxLocalDistanceSquared
    [coarseSegment, ~, ~, ~] = localSearchCoarse(x, y, road);
    refineRadius = int32(road.coarseRefineRadius);
    firstIndex = max(int32(1), coarseSegment - refineRadius);
    lastIndex = min(numSegments, coarseSegment + refineRadius);
    [segmentIndex, projection, lateralDistance, distanceSquared] = ...
        localSearchSegments(x, y, firstIndex, lastIndex, road);
end

isValidProjection = isfinite(distanceSquared) && segmentIndex >= int32(1) && segmentIndex <= numSegments;
end

function startIndex = localPreviousIndex(iuPrev, numSegments)
if isfinite(iuPrev)
    startIndex = int32(floor(iuPrev));
else
    startIndex = int32(1);
end
startIndex = min(max(startIndex, int32(1)), numSegments);
end

function [bestIndex, bestProjection, bestLateral, bestDistanceSquared] = localSearchCoarse(x, y, road)
bestIndex = int32(1);
bestProjection = 0.0;
bestLateral = 0.0;
bestDistanceSquared = realmax("double");

for coarseIndex = 1:numel(road.coarseIndex)
    candidateIndex = int32(road.coarseIndex(coarseIndex));
    [projection, lateralDistance, distanceSquared] = localProjectSegment(x, y, candidateIndex, road);
    if distanceSquared < bestDistanceSquared
        bestDistanceSquared = distanceSquared;
        bestProjection = projection;
        bestLateral = lateralDistance;
        bestIndex = candidateIndex;
    end
end
end

function [bestIndex, bestProjection, bestLateral, bestDistanceSquared] = localSearchSegments( ...
    x, y, firstIndex, lastIndex, road)
bestIndex = firstIndex;
bestProjection = 0.0;
bestLateral = 0.0;
bestDistanceSquared = realmax("double");

for segmentIndex = firstIndex:lastIndex
    [projection, lateralDistance, distanceSquared] = localProjectSegment(x, y, segmentIndex, road);
    if distanceSquared < bestDistanceSquared
        bestDistanceSquared = distanceSquared;
        bestProjection = projection;
        bestLateral = lateralDistance;
        bestIndex = segmentIndex;
    end
end
end

function [projection, lateralDistance, distanceSquared] = localProjectSegment(x, y, segmentIndex, road)
nextIndex = segmentIndex + int32(1);
x1 = double(road.xRef(segmentIndex));
y1 = double(road.yRef(segmentIndex));
x2 = double(road.xRef(nextIndex));
y2 = double(road.yRef(nextIndex));
segmentX = x2 - x1;
segmentY = y2 - y1;
pointX = x - x1;
pointY = y - y1;
segmentLengthSquared = segmentX*segmentX + segmentY*segmentY;

if segmentLengthSquared > 0.0
    projection = (pointX*segmentX + pointY*segmentY)/segmentLengthSquared;
else
    projection = 0.0;
end
projection = min(max(projection, 0.0), 1.0);

closestX = x1 + projection*segmentX;
closestY = y1 + projection*segmentY;
deltaX = x - closestX;
deltaY = y - closestY;
distanceSquared = deltaX*deltaX + deltaY*deltaY;
lateralDistance = (segmentX*pointY - segmentY*pointX)/sqrt(max(segmentLengthSquared, eps));
end

function uValue = localInterpolateU(segmentIndex, projection, road)
u1 = double(road.u(segmentIndex));
u2 = double(road.u(segmentIndex + int32(1)));
uValue = u1 + projection*(u2 - u1);
end

function tf = localInsideUv(uValue, vValue, road)
tf = uValue >= road.uMin && uValue <= road.uMax && vValue >= road.vMin && vValue <= road.vMax;
end

function zValue = localInterpolateElevation( ...
    uValue, vValue, uIndex, vIndex, uFraction, vFraction, road)
rawZ = localInterpolateGridAt(road.z, uIndex, vIndex, uFraction, vFraction);
slopeZ = road.zBeg + (uValue - road.uMin)*road.sBeg;
bankValue = localInterpolateVectorAt(road.bank, uIndex, uFraction);
clampedV = min(max(vValue, road.vMin), road.vMax);
zValue = rawZ + slopeZ + clampedV*double(bankValue);
end

function value = localInterpolateGridAt(grid, uIndex, vIndex, uFraction, vFraction)
z00 = double(grid(uIndex, vIndex));
z10 = double(grid(uIndex + int32(1), vIndex));
z01 = double(grid(uIndex, vIndex + int32(1)));
z11 = double(grid(uIndex + int32(1), vIndex + int32(1)));
value = (1.0 - uFraction)*(1.0 - vFraction)*z00 + uFraction*(1.0 - vFraction)*z10 + ...
    (1.0 - uFraction)*vFraction*z01 + uFraction*vFraction*z11;
end

function [uIndex, fraction] = localFindUInterval(uValue, road)
rawIndex = floor((uValue - road.uMin)/road.uInc) + 1.0;
uIndex = int32(min(max(rawIndex, 1.0), road.numU - 1.0));
u1 = double(road.u(uIndex));
u2 = double(road.u(uIndex + int32(1)));
fraction = (uValue - u1)/max(u2 - u1, eps);
fraction = min(max(fraction, 0.0), 1.0);
end

function [vIndex, fraction] = localFindVInterval(vValue, road)
if road.isVRegular ~= 0.0 && road.vInc ~= 0.0
    rawIndex = floor((vValue - road.vMin)/road.vInc) + 1.0;
    vIndex = int32(min(max(rawIndex, 1.0), road.numV - 1.0));
else
    vIndex = int32(1);
    for candidateIndex = int32(1):int32(road.numV - 1.0)
        if vValue >= double(road.v(candidateIndex)) && vValue <= double(road.v(candidateIndex + int32(1)))
            vIndex = candidateIndex;
            break
        end
    end
end
v1 = double(road.v(vIndex));
v2 = double(road.v(vIndex + int32(1)));
fraction = (vValue - v1)/max(v2 - v1, eps);
fraction = min(max(fraction, 0.0), 1.0);
end

function value = localInterpolateVectorAt(channel, uIndex, fraction)
value1 = double(channel(uIndex));
value2 = double(channel(uIndex + int32(1)));
value = value1 + fraction*(value2 - value1);
end

function [qx, qy] = localAnglesFromNormal( ...
    uIndex, vIndex, uFraction, vFraction, phiValue, road)
normalX = localInterpolateGridAt(road.normalX, uIndex, vIndex, uFraction, vFraction);
normalY = localInterpolateGridAt(road.normalY, uIndex, vIndex, uFraction, vFraction);
normalZ = localInterpolateGridAt(road.normalZ, uIndex, vIndex, uFraction, vFraction);
normalLength = sqrt(normalX*normalX + normalY*normalY + normalZ*normalZ);
if normalLength <= eps || ~isfinite(normalLength)
    slopeValue = localInterpolateVectorAt(road.slope, uIndex, uFraction);
    bankValue = localInterpolateVectorAt(road.bank, uIndex, uFraction);
    qx = atan(double(bankValue));
    qy = -atan(double(slopeValue));
    return
end
normalX = normalX/normalLength;
normalY = normalY/normalLength;
normalZ = normalZ/normalLength;
if normalZ < 0.0
    normalX = -normalX;
    normalY = -normalY;
    normalZ = -normalZ;
end
forwardNormal = normalX*cos(double(phiValue)) + normalY*sin(double(phiValue));
lateralNormal = -normalX*sin(double(phiValue)) + normalY*cos(double(phiValue));
qx = atan2(-lateralNormal, sqrt(forwardNormal*forwardNormal + normalZ*normalZ));
qy = atan2(forwardNormal, normalZ);
end
