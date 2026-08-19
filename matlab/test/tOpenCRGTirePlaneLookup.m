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