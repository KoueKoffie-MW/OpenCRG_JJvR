classdef tOpenCRGRoadSurfaceLookup < matlab.unittest.TestCase
    %TOPENCRGROADSURFACELOOKUP Tests for matched CRG road-surface lookup data.

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
        function exporterAutoDiscoversMatchedFiles(testCase)
            fixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture());
            roadFile = localWriteMatchedCrgSet(testCase, fixture.Folder);

            [road, metadata] = crg_export_road_surface_lookup(roadFile, "", ...
                Precision="single", RequireMatchedFiles=true, Write=false);

            testCase.verifyEqual(road.hasFriction, 1.0);
            testCase.verifyEqual(road.hasNormals, 1.0);
            testCase.verifyEqual(metadata.HasFriction, true);
            testCase.verifyEqual(metadata.HasNormals, true);
            testCase.verifyTrue(endsWith(metadata.MatchedFiles.Friction, "_friction.crg"));
            testCase.verifyEqual(string(class(road.friction)), "single");
        end

        function runtimeUsesFrictionAndNormals(testCase)
            fixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture());
            roadFile = localWriteMatchedCrgSet(testCase, fixture.Folder);
            road = crg_export_road_surface_lookup(roadFile, "", Precision="double", RequireMatchedFiles=true, Write=false);
            data = crg_read(roadFile);
            uvQuery = [data.head.ubeg + 5.0*data.head.uinc, 0.0];
            xyQuery = crg_eval_uv2xy(data, uvQuery);
            [zReference, data] = crg_eval_uv2z(data, uvQuery);
            phiReference = crg_eval_u2phi(data, uvQuery(1));

            [px, py, pz, iuCurr, qx, qy, qz, mu] = crg_road_surface_lookup_step( ...
                xyQuery(1), xyQuery(2), -1.0, xyQuery(1), xyQuery(2), 5.0, road);

            testCase.verifyEqual([px, py], xyQuery, AbsTol=1e-12);
            testCase.verifyEqual(pz, zReference, AbsTol=1e-5);
            testCase.verifyGreaterThanOrEqual(iuCurr, 1.0);
            testCase.verifyEqual(qx, 0.0, AbsTol=1e-12);
            testCase.verifyEqual(qy, 0.0, AbsTol=1e-12);
            testCase.verifyEqual(qz, phiReference, AbsTol=1e-12);
            testCase.verifyEqual(mu, 0.82, AbsTol=1e-6);
        end

        function missingMatchedFilesFallbackToDefaults(testCase)
            crgFile = fullfile(testCase.CrgTextFolder, "handmade_curved.crg");
            road = crg_export_road_surface_lookup(crgFile, "", Write=false, RequireMatchedFiles=false);
            data = crg_read(crgFile);
            uvQuery = [data.head.ubeg + 3.0*data.head.uinc, 0.0];
            xyQuery = crg_eval_uv2xy(data, uvQuery);

            [~, ~, pz, iuCurr, ~, ~, ~, mu] = crg_road_surface_lookup_step( ...
                xyQuery(1), xyQuery(2), -1.0, xyQuery(1), xyQuery(2), 3.0, road);

            testCase.verifyEqual(road.hasFriction, 0.0);
            testCase.verifyEqual(road.hasNormals, 0.0);
            testCase.verifyTrue(isfinite(pz));
            testCase.verifyGreaterThanOrEqual(iuCurr, 1.0);
            testCase.verifyEqual(mu, 1.0);
        end

        function runtimeRecoversTiltFromNormal(testCase)
            crgFile = fullfile(testCase.CrgTextFolder, "handmade_curved.crg");
            road = crg_export_road_surface_lookup(crgFile, "", ...
                Precision="double", Write=false, RequireMatchedFiles=false);
            data = crg_read(crgFile);
            rollExpected = 0.20;
            pitchExpected = -0.10;
            phiGrid = double(road.phi(:));
            cosRoll = cos(rollExpected);
            sinRoll = sin(rollExpected);
            cosPitch = cos(pitchExpected);
            sinPitch = sin(pitchExpected);
            normalX = cos(phiGrid).*sinPitch*cosRoll + sin(phiGrid)*sinRoll;
            normalY = sin(phiGrid).*sinPitch*cosRoll - cos(phiGrid)*sinRoll;
            normalZ = repmat(cosPitch*cosRoll, size(phiGrid));
            road.normalX = repmat(normalX, 1, road.numV);
            road.normalY = repmat(normalY, 1, road.numV);
            road.normalZ = repmat(normalZ, 1, road.numV);
            road.hasNormals = 1.0;
            uvQuery = [data.head.ubeg + 5.0*data.head.uinc, 0.0];
            xyQuery = crg_eval_uv2xy(data, uvQuery);

            [~, ~, ~, ~, qx, qy] = crg_road_surface_lookup_step( ...
                xyQuery(1), xyQuery(2), 0.0, xyQuery(1), xyQuery(2), 5.0, road);

            testCase.verifyEqual(qx, rollExpected, AbsTol=1e-12);
            testCase.verifyEqual(qy, pitchExpected, AbsTol=1e-12);
        end

        function runtimeBuildsMex(testCase)
            testCase.assumeNotEmpty(mex.getCompilerConfigurations("C", "Selected"));
            fixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture());
            roadFile = localWriteMatchedCrgSet(testCase, fixture.Folder);
            road = crg_export_road_surface_lookup(roadFile, "", Precision="single", RequireMatchedFiles=true, Write=false);
            inputTypes = {coder.typeof(0.0), coder.typeof(0.0), coder.typeof(0.0), ...
                coder.typeof(0.0), coder.typeof(0.0), coder.typeof(0.0), coder.Constant(road)};
            currentFolder = pwd();
            cleanupFolder = onCleanup(@() cd(currentFolder));

            clear("crg_road_surface_lookup_step_mex");
            cd(fixture.Folder);
            codegen("crg_road_surface_lookup_step", "-args", inputTypes, "-d", fixture.Folder);
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fixture.Folder));
            [~, ~, pz, iuCurr, ~, ~, ~, mu] = crg_road_surface_lookup_step_mex( ...
                0.0, 0.0, -1.0, 0.0, 0.0, 1.0, road);
            clear cleanupFolder

            testCase.verifyTrue(isfinite(pz));
            testCase.verifyGreaterThanOrEqual(iuCurr, 1.0);
            testCase.verifyEqual(mu, 0.82, AbsTol=1e-6);
        end
    end
end

function roadFile = localWriteMatchedCrgSet(testCase, folder)
sourceFile = fullfile(testCase.CrgTextFolder, "handmade_curved.crg");
baseData = crg_read(sourceFile);
roadFile = fullfile(folder, "synthetic_road.crg");
localWriteCrg(baseData, roadFile, baseData.z);
localWriteCrg(baseData, fullfile(folder, "synthetic_friction.crg"), single(0.82*ones(size(baseData.z))));
localWriteCrg(baseData, fullfile(folder, "synthetic_nx.crg"), single(zeros(size(baseData.z))));
localWriteCrg(baseData, fullfile(folder, "synthetic_ny.crg"), single(zeros(size(baseData.z))));
localWriteCrg(baseData, fullfile(folder, "synthetic_nz.crg"), single(ones(size(baseData.z))));
end

function localWriteCrg(baseData, fileName, grid)
data = baseData;
data.filenm = fileName;
data.z = single(grid);
data.ct = {"Synthetic CRG lookup test file"};
crg_write(crg_single(data), fileName, "LRFI");
end
