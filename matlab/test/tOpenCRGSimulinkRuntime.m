classdef tOpenCRGSimulinkRuntime < matlab.unittest.TestCase
    %TOPENCRGSIMULINKRUNTIME Tests for the C API backed Simulink runtime.

    properties
        Repository (1, 1) string
        MatlabFolder (1, 1) string
        SimulinkFolder (1, 1) string
        CrgTextFolder (1, 1) string
    end

    methods (TestClassSetup)
        function addSourcePaths(testCase)
            testFolder = string(fileparts(mfilename("fullpath")));
            testCase.MatlabFolder = fileparts(testFolder);
            testCase.Repository = fileparts(testCase.MatlabFolder);
            testCase.SimulinkFolder = fullfile(testCase.MatlabFolder, "simulink");
            testCase.CrgTextFolder = fullfile(testCase.Repository, "crg-txt");

            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testCase.MatlabFolder));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(testCase.MatlabFolder, "lib")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testCase.SimulinkFolder));
        end
    end

    methods (Test)
        function sourceInfoListsRuntimeAndBaseSources(testCase)
            sourceInfo = crg_runtime_source_info();

            testCase.verifyTrue(isfile(sourceInfo.RuntimeSource));
            testCase.verifyTrue(isfile(sourceInfo.MexSource));
            testCase.verifyTrue(isfile(sourceInfo.SFunctionSource));
            testCase.verifyGreaterThanOrEqual(numel(sourceInfo.OpenCrgSources), 8);
            testCase.verifyTrue(all(isfile(string(sourceInfo.OpenCrgSources))));
        end

        function runtimeExportWritesConfiguration(testCase)
            fixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture());
            crgFile = fullfile(testCase.CrgTextFolder, "handmade_curved.crg");
            matFile = fullfile(fixture.Folder, "runtime.mat");

            runtime = crg_export_simulink_runtime(crgFile, matFile, ...
                CreateSimulinkLookupTable=false);
            loaded = load(matFile);

            testCase.verifyTrue(isfile(matFile));
            testCase.verifyEqual(runtime.SFunctionName, "crg_sfun_xy2z");
            testCase.verifyEqual(runtime.CodegenFunction, "crg_runtime_xy2z_file");
            testCase.verifyEqual(runtime.SourceMode, "Both");
            testCase.verifyEqual(loaded.runtime.SFunctionName, runtime.SFunctionName);
            testCase.verifyEqual(loaded.lookup.Table, runtime.Lookup.Table);
        end

        function runtimeMexMatchesMatlabReference(testCase)
            testCase.assumeNotEmpty(mex.getCompilerConfigurations("C", "Selected"));
            crgFile = fullfile(testCase.CrgTextFolder, "handmade_curved.crg");
            buildInfo = crg_build_simulink_runtime(Target="mex", Verbose=false);
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(buildInfo.OutputFolder));

            data = crg_read(crgFile);
            uvQuery = [data.head.ubeg + 5*data.head.uinc, 0.0];
            xyQuery = crg_eval_uv2xy(data, uvQuery);

            runtimeHandle = crg_runtime_mex("open", crgFile, 50);
            testCase.addTeardown(@() crg_runtime_mex("close", runtimeHandle));
            [u, v, z, phi, curvature, status] = crg_runtime_mex("step", ...
                runtimeHandle, xyQuery(1), xyQuery(2), false);
            [zReference, data] = crg_eval_uv2z(data, [u v]);
            phiReference = crg_eval_u2phi(data, u);
            curvatureReference = crg_eval_u2crv(data, u);

            testCase.verifyEqual(status, 0);
            testCase.verifyEqual(z, zReference, AbsTol=1e-4);
            testCase.verifyEqual(phi, phiReference, AbsTol=1e-3);
            testCase.verifyEqual(curvature, curvatureReference, AbsTol=1e-3);
        end

        function sFunctionCompilesInSimulinkModel(testCase)
            testCase.assumeNotEmpty(mex.getCompilerConfigurations("C", "Selected"));
            testCase.assumeNotEmpty(ver("simulink"));
            crgFile = fullfile(testCase.CrgTextFolder, "handmade_curved.crg");
            buildInfo = crg_build_simulink_runtime(Target="sfunction", Verbose=false);
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(buildInfo.OutputFolder));

            modelName = "crg_sfun_runtime_test";
            if bdIsLoaded(modelName)
                close_system(modelName, 0);
            end
            new_system(modelName);
            testCase.addTeardown(@() close_system(modelName, 0));

            data = crg_read(crgFile);
            xyQuery = crg_eval_uv2xy(data, [data.head.ubeg + 5*data.head.uinc, 0.0]);

            add_block("simulink/Sources/Constant", modelName + "/x", Value=num2str(xyQuery(1)));
            add_block("simulink/Sources/Constant", modelName + "/y", Value=num2str(xyQuery(2)));
            add_block("simulink/Sources/Constant", modelName + "/reset", Value="0");
            add_block("simulink/User-Defined Functions/S-Function", modelName + "/OpenCRG", ...
                FunctionName="crg_sfun_xy2z", Parameters="'" + crgFile + "', 50");

            for outputIndex = 1:6
                add_block("simulink/Sinks/Terminator", modelName + "/out" + outputIndex);
            end

            add_line(modelName, "x/1", "OpenCRG/1");
            add_line(modelName, "y/1", "OpenCRG/2");
            add_line(modelName, "reset/1", "OpenCRG/3");
            for outputIndex = 1:6
                add_line(modelName, "OpenCRG/" + outputIndex, "out" + outputIndex + "/1");
            end

            set_param(modelName, "SimulationCommand", "Update");
        end

        function codegenFunctionBuildsMex(testCase)
            testCase.assumeNotEmpty(mex.getCompilerConfigurations("C", "Selected"));
            fixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture());
            crgFile = char(fullfile(testCase.CrgTextFolder, "handmade_curved.crg"));
            inputTypes = {coder.Constant(crgFile), coder.typeof(0.0), coder.typeof(0.0), ...
                coder.typeof(false), coder.typeof(50.0)};
            cfg = coder.config("mex");
            currentFolder = pwd();
            cleanupFolder = onCleanup(@() cd(currentFolder));

            clear("crg_runtime_xy2z_file_mex");
            cd(fixture.Folder);
            codegen("crg_runtime_xy2z_file", "-config", cfg, "-args", inputTypes, "-d", fixture.Folder);
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fixture.Folder));

            [u, v, z, phi, curvature, status] = crg_runtime_xy2z_file_mex(crgFile, 0.0, 0.0, false, 50.0);
            clear cleanupFolder

            testCase.verifyEqual(status, int32(0));
            testCase.verifyTrue(all(isfinite([u v z phi curvature])));
        end
    end
end
