classdef tOpenCRGSurfaceBundle < matlab.unittest.TestCase
    %TOPENCRGSURFACEBUNDLE Tests for OpenCRG surface bundle generation and lookup.

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
        function createsAndLoadsSelfContainedBundle(testCase)
            fixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture());
            sourceFile = fullfile(testCase.CrgTextFolder, "handmade_curved.crg");
            outputFolder = fullfile(fixture.Folder, "bundle");

            [createdBundle, manifest] = crg_create_surface_bundle(sourceFile, outputFolder, ...
                BundleName="curved", DataFormat="LRFI");
            [loadedBundle, metadata] = crg_export_surface_bundle_lookup(createdBundle.ManifestFile, Precision="double");

            testCase.verifyTrue(isfile(createdBundle.ManifestFile));
            testCase.verifyTrue(isfile(createdBundle.Files.Road));
            testCase.verifyTrue(isfile(createdBundle.Files.MaterialId));
            testCase.verifyEqual(manifest.Defaults.OnRoad.Friction, 1.0);
            testCase.verifyEqual(manifest.Defaults.OffRoad.Friction, 0.7);
            testCase.verifyEqual(manifest.Defaults.OffRoad.MaterialId, 2);
            testCase.verifyEqual(manifest.Defaults.OnRoad.RollingResistance, 0.015, AbsTol=1e-12);
            testCase.verifySize(loadedBundle.friction, size(loadedBundle.z));
            testCase.verifyEqual(metadata.BundleName, "curved");
        end

        function generatedNormalsAreUnitAndUpward(testCase)
            fixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture());
            sourceFile = fullfile(testCase.CrgTextFolder, "handmade_curved.crg");

            createdBundle = crg_create_surface_bundle(sourceFile, fixture.Folder, ...
                BundleName="smooth", NormalSmoothingSigma=[0.05 0.05]);
            loadedBundle = crg_export_surface_bundle_lookup(createdBundle.ManifestFile, Precision="double");
            normalLength = sqrt(loadedBundle.normalX.^2 + loadedBundle.normalY.^2 + loadedBundle.normalZ.^2);

            testCase.verifyEqual(normalLength, ones(size(normalLength)), AbsTol=5e-6);
            testCase.verifyGreaterThanOrEqual(min(loadedBundle.normalZ, [], "all"), 0.0);
        end

        function terrainPreparationRejectsPartialNormals(testCase)
            terrain = struct( ...
                "x", [0 1], ...
                "y", [0 1], ...
                "z", zeros(2), ...
                "normalX", zeros(2));

            testCase.verifyError(@() crg_prepare_terrain_grid(terrain), "CRG:terrainGridError");
        end

        function lookupBlendsRoadAndTerrainProperties(testCase)
            fixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture());
            sourceFile = fullfile(testCase.CrgTextFolder, "handmade_curved.crg");
            createdBundle = crg_create_surface_bundle(sourceFile, fixture.Folder, ...
                BundleName="lookup", DefaultBlendWidth=2.0);
            loadedBundle = crg_export_surface_bundle_lookup(createdBundle.ManifestFile, Precision="double");
            terrain = localTerrainForRoad(loadedBundle.RoadData);
            preparedTerrain = crg_prepare_terrain_grid(terrain);
            uValue = loadedBundle.RoadData.head.ubeg + 5.0*loadedBundle.RoadData.head.uinc;
            [onRoadPoint, roadData] = crg_eval_uv2xy(loadedBundle.RoadData, [uValue 0.0]);
            [blendPoint, roadData] = crg_eval_uv2xy(roadData, [uValue roadData.head.vmax + 1.0]);
            [terrainPoint, ~] = crg_eval_uv2xy(roadData, [uValue roadData.head.vmax + 5.0]);

            onRoadSurface = crg_surface_bundle_terrain_lookup( ...
                onRoadPoint(1), onRoadPoint(2), loadedBundle, preparedTerrain);
            blendSurface = crg_surface_bundle_terrain_lookup( ...
                blendPoint(1), blendPoint(2), loadedBundle, preparedTerrain);
            terrainSurface = crg_surface_bundle_terrain_lookup( ...
                terrainPoint(1), terrainPoint(2), loadedBundle, preparedTerrain);

            testCase.verifyEqual(onRoadSurface.Status, "road");
            testCase.verifyEqual(onRoadSurface.Friction, 1.0, AbsTol=1e-6);
            testCase.verifyEqual(onRoadSurface.MaterialId, 1.0);
            testCase.verifyEqual(blendSurface.Status, "blend");
            testCase.verifyGreaterThan(blendSurface.RoadWeight, 0.0);
            testCase.verifyLessThan(blendSurface.RoadWeight, 1.0);
            testCase.verifyEqual(terrainSurface.Status, "terrain");
            testCase.verifyEqual(terrainSurface.Friction, 0.4, AbsTol=1e-6);
            testCase.verifyEqual(terrainSurface.MaterialId, 9.0);
        end
    end
end

function terrain = localTerrainForRoad(roadData)
xMinimum = min(roadData.rx) - 10.0;
xMaximum = max(roadData.rx) + 10.0;
yMinimum = min(roadData.ry) - 10.0;
yMaximum = max(roadData.ry) + 10.0;
terrain = struct( ...
    "x", linspace(xMinimum, xMaximum, 61), ...
    "y", linspace(yMinimum, yMaximum, 61), ...
    "z", 3.0*ones(61), ...
    "friction", 0.4*ones(61), ...
    "materialId", 9.0*ones(61), ...
    "roughness", 0.2*ones(61), ...
    "wetness", 0.3*ones(61), ...
    "temperatureC", 10.0*ones(61), ...
    "rollingResistance", 0.02*ones(61));
end
