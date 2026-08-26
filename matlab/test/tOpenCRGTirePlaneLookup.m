classdef tOpenCRGTirePlaneLookup < matlab.unittest.TestCase
    %TOPENCRGTIREPLANELOOKUP Tests for CRG-native tire-plane lookup runtime.

    properties
        Repository (1, 1) string
        MatlabFolder (1, 1) string
        CrgTextFolder (1, 1) string
    end

    methods (TestClassSetup)
        function addSourcePaths(testCase)
            testFolder = string(fileparts(mfilename("fullpath")));
            testCase.MatlabFolder = fileparts(testFolder);
            testCase.Repository = fileparts(testCase.MatlabFolder);
            testCase.CrgTextFolder = fullfile(testCase.Repository, "crg-txt");

            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testCase.MatlabFolder));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(testCase.MatlabFolder, "lib")));
        end
    end

    methods (Test)
        function exporterWritesCompactRoadStruct(testCase)
            fixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture());
            crgFile = fullfile(testCase.CrgTextFolder, "handmade_curved.crg");
            matFile = fullfile(fixture.Folder, "roadLookup.mat");

            [road, metadata] = crg_export_tire_plane_lookup(crgFile, matFile, Precision="single");
            loaded = load(matFile, "road", "metadata");

            testCase.verifyTrue(isfile(matFile));
            testCase.verifyEqual(string(class(road.z)), "single");
            testCase.verifyEqual(size(road.z), [road.numU, road.numV]);
            testCase.verifyEqual(metadata.RuntimeFunction, "crg_tire_plane_lookup_step");
            testCase.verifyEqual(loaded.metadata.GridSize, metadata.GridSize);
            testCase.verifyEqual(size(loaded.road.z), size(road.z));
        end

        function lookupStepMatchesMatlabReference(testCase)
            crgFile = fullfile(testCase.CrgTextFolder, "handmade_curved.crg");
            data = crg_read(crgFile);
            road = crg_export_tire_plane_lookup(data, "", Precision="double", Write=false);
            uvQuery = [data.head.ubeg + 5.35*data.head.uinc, 0.25];
            xyQuery = crg_eval_uv2xy(data, uvQuery);
            [zReference, data] = crg_eval_uv2z(data, uvQuery);
            phiReference = crg_eval_u2phi(data, uvQuery(1));

            [px, py, pz, iuCurr, qx, qy, qz] = crg_tire_plane_lookup_step( ...
                xyQuery(1), xyQuery(2), -1.0, xyQuery(1), xyQuery(2), 5.0, road);

            testCase.verifyEqual([px, py], xyQuery, AbsTol=1e-12);
            testCase.verifyEqual(pz, zReference, AbsTol=1e-5);
            testCase.verifyEqual(qz, phiReference, AbsTol=1e-12);
            testCase.verifyGreaterThanOrEqual(iuCurr, 1.0);
            testCase.verifyTrue(all(isfinite([qx, qy, qz])));
        end

        function lookupStepFallsBackOutsideRoad(testCase)
            crgFile = fullfile(testCase.CrgTextFolder, "handmade_curved.crg");
            road = crg_export_tire_plane_lookup(crgFile, "", Precision="single", Write=false);

            [~, ~, pz, iuCurr, qx, qy, qz] = crg_tire_plane_lookup_step( ...
                0.0, 1.0e6, 12.5, 0.0, 0.0, 3.0, road);

            testCase.verifyEqual(pz, 12.5);
            testCase.verifyEqual(iuCurr, 3.0);
            testCase.verifyEqual([qx, qy, qz], [0.0, 0.0, 0.0]);
        end

        function lookupStepRecoversFromStaleSegment(testCase)
            road = localCreateLongLookupRoad();
            queryPositions = 0.0:5.0:20.0;
            previousHeight = -1.0;
            previousIndex = NaN;
            previousX = NaN;

            for queryIndex = 1:numel(queryPositions)
                x = queryPositions(queryIndex);
                [~, ~, expectedHeight, expectedIndex] = ...
                    crg_tire_plane_lookup_step(x, 0.0, previousHeight, x, 0.0, NaN, road);
                [~, ~, actualHeight, actualIndex] = ...
                    crg_tire_plane_lookup_step( ...
                    x, 0.0, previousHeight, previousX, 0.0, previousIndex, road);

                testCase.verifyEqual(actualHeight, expectedHeight, AbsTol=1e-12);
                testCase.verifyEqual(actualIndex, expectedIndex);
                previousHeight = actualHeight;
                previousIndex = actualIndex;
                previousX = x;
            end
        end
        function lookupStepBuildsMex(testCase)
            testCase.assumeNotEmpty(mex.getCompilerConfigurations("C", "Selected"));
            fixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture());
            crgFile = fullfile(testCase.CrgTextFolder, "handmade_curved.crg");
            road = crg_export_tire_plane_lookup(crgFile, "", Precision="single", Write=false);
            inputTypes = {coder.typeof(0.0), coder.typeof(0.0), coder.typeof(0.0), ...
                coder.typeof(0.0), coder.typeof(0.0), coder.typeof(0.0), coder.Constant(road)};
            currentFolder = pwd();
            cleanupFolder = onCleanup(@() cd(currentFolder));

            clear("crg_tire_plane_lookup_step_mex");
            cd(fixture.Folder);
            codegen("crg_tire_plane_lookup_step", "-args", inputTypes, "-d", fixture.Folder);
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fixture.Folder));
            [~, ~, pz, iuCurr, ~, ~, ~] = crg_tire_plane_lookup_step_mex( ...
                0.0, 0.0, -1.0, 0.0, 0.0, 1.0, road);
            clear cleanupFolder

            testCase.verifyTrue(isfinite(pz));
            testCase.verifyGreaterThanOrEqual(iuCurr, 1.0);
        end
    end
end
function road = localCreateLongLookupRoad()
u = (0.0:0.1:20.0)';
v = [-1.0; 0.0; 1.0];
numU = numel(u);
numV = numel(v);
numSegments = numU - 1;
xRef = u;
yRef = zeros(size(u));
segmentX = diff(xRef);
segmentY = diff(yRef);
lengthSquared = segmentX.^2 + segmentY.^2;
coarseIndex = unique(int32([1:25:numSegments, numSegments]))';

road = struct( ...
    "u", u, ...
    "v", v, ...
    "z", repmat(0.02*u, 1, numV), ...
    "xRef", xRef, ...
    "yRef", yRef, ...
    "phi", zeros(numU, 1), ...
    "slope", zeros(numU, 1), ...
    "bank", zeros(numU, 1), ...
    "segmentX", segmentX, ...
    "segmentY", segmentY, ...
    "invSegmentLengthSquared", 1.0./lengthSquared, ...
    "invSegmentLength", 1.0./sqrt(lengthSquared), ...
    "uDelta", diff(u), ...
    "coarseIndex", coarseIndex, ...
    "numU", double(numU), ...
    "numV", double(numV), ...
    "uMin", u(1), ...
    "uMax", u(end), ...
    "uInc", 0.1, ...
    "vMin", v(1), ...
    "vMax", v(end), ...
    "vInc", 1.0, ...
    "isVRegular", 1.0, ...
    "zBeg", 0.0, ...
    "sBeg", 0.0, ...
    "fastSearchRadius", 6.0, ...
    "localSearchRadius", 25.0, ...
    "coarseRefineRadius", 50.0, ...
    "maxLocalDistance", 40.0, ...
    "hasFriction", 1.0, ...
    "hasNormals", 1.0, ...
    "friction", 0.8*ones(numU, numV), ...
    "normalX", zeros(numU, numV), ...
    "normalY", zeros(numU, numV), ...
    "normalZ", ones(numU, numV));
end