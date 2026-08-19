classdef tOpenCRGMeshExport < matlab.unittest.TestCase
    %TOPENCRGMESHEXPORT Tests for OpenCRG mesh, FBX, and Sim3D exports.

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
        function meshExportCreatesPhysicsVolume(testCase)
            crgFile = fullfile(testCase.CrgTextFolder, "handmade_curved.crg");

            mesh = crg_export_mesh(crgFile, ...
                NumLongitudinalSamples=12, ...
                NumLateralSamples=5, ...
                PhysicsMesh=true, ...
                Thickness=0.1);

            testCase.verifySize(mesh.Metadata.GridSize, [1 2]);
            testCase.verifyEqual(mesh.Metadata.SurfaceVertexCount, 60);
            testCase.verifyEqual(size(mesh.Vertices, 1), 120);
            testCase.verifyEqual(size(mesh.Normals), size(mesh.Vertices));
            testCase.verifyEqual(size(mesh.UV, 1), size(mesh.Vertices, 1));
            testCase.verifyGreaterThan(size(mesh.Faces, 1), 2*(12-1)*(5-1));
            testCase.verifyTrue(all(isfinite(mesh.Vertices), "all"));
            testCase.verifyTrue(all(isfinite(mesh.Normals), "all"));
            testCase.verifyTrue(all(mesh.Faces(:) >= 1));
            testCase.verifyTrue(all(mesh.Faces(:) <= size(mesh.Vertices, 1)));
        end

        function fbxWriterCreatesFileWhenBlenderExists(testCase)
            blenderExecutable = testCase.findBlenderExecutable();
            testCase.assumeTrue(blenderExecutable ~= "", "Blender executable is unavailable.");
            fixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture());
            crgFile = fullfile(testCase.CrgTextFolder, "handmade_curved.crg");
            fbxFile = fullfile(fixture.Folder, "handmade_curved.fbx");

            [writtenFile, mesh] = crg_write_fbx(crgFile, fbxFile, ...
                BlenderExecutable=blenderExecutable, ...
                NumLongitudinalSamples=10, ...
                NumLateralSamples=5, ...
                PhysicsMesh=true);

            testCase.verifyEqual(writtenFile, string(fbxFile));
            testCase.verifyTrue(isfile(fbxFile));
            testCase.verifyGreaterThan(dir(fbxFile).bytes, 0);
            testCase.verifyEqual(mesh.Metadata.FBXFile, string(fbxFile));
        end

        function sim3dActorUsesMeshDataWhenAvailable(testCase)
            testCase.assumeTrue(exist("sim3d.Actor", "class") == 8, "sim3d.Actor is unavailable.");
            crgFile = fullfile(testCase.CrgTextFolder, "handmade_curved.crg");

            [actor, mesh] = crg_create_sim3d_actor(crgFile, ...
                NumLongitudinalSamples=8, ...
                NumLateralSamples=4, ...
                PhysicsMesh=false);

            testCase.verifyClass(actor, "sim3d.Actor");
            testCase.verifyEqual(actor.UserData.SurfaceVertexCount, mesh.Metadata.SurfaceVertexCount);
            testCase.verifyEqual(mesh.Metadata.PhysicsMesh, false);
        end
    end

    methods (Static, Access = private)
        function blenderExecutable = findBlenderExecutable()
            candidates = [
                "C:\Program Files\Blender Foundation\Blender 5.0\blender.exe"
                "C:\Program Files\Blender Foundation\Blender 4.5\blender.exe"
                "C:\Program Files\Blender Foundation\Blender 4.4\blender.exe"
                "C:\Program Files\Blender Foundation\Blender 4.3\blender.exe"];
            blenderExecutable = "";
            for candidateIndex = 1:numel(candidates)
                if isfile(candidates(candidateIndex))
                    blenderExecutable = candidates(candidateIndex);
                    return
                end
            end
        end
    end
end
