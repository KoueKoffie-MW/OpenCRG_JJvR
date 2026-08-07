classdef tOpenCRGModernization < matlab.unittest.TestCase
    %TOPENCRGMODERNIZATION Regression tests for MATLAB modernization work.

    properties
        Repository (1, 1) string
        MatlabFolder (1, 1) string
        CrgTextFolder (1, 1) string
        CrgBinaryFolder (1, 1) string
    end

    properties (TestParameter)
        representativeFile = makeRepresentativeFiles()
        borderCase = makeBorderCases()
    end

    methods (TestClassSetup)
        function addSourcePaths(testCase)
            testFolder = string(fileparts(mfilename("fullpath")));
            testCase.MatlabFolder = fileparts(testFolder);
            testCase.Repository = fileparts(testCase.MatlabFolder);
            testCase.CrgTextFolder = fullfile(testCase.Repository, "crg-txt");
            testCase.CrgBinaryFolder = fullfile(testCase.Repository, "crg-bin");

            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testCase.MatlabFolder));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(testCase.MatlabFolder, "lib")));
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testFolder));
        end
    end

    methods (Test)
        function selectedFormattedChannelReturnsSingleColumn(testCase)
            file = fullfile(testCase.CrgTextFolder, "handmade_curved.crg");
            allChannels = ipl_read(file);
            selected = ipl_read(file, struct("channel", "long section at v =  0.000,m"));
            channelIndex = find(strcmp(selected.kd_def{1}, allChannels.kd_def), 1);

            testCase.verifyEqual(size(selected.kd_dat, 2), 1);
            testCase.verifyEqual(selected.kd_dat, allChannels.kd_dat(:, channelIndex));
        end

        function longRecordsAreTruncatedOnWrite(testCase)
            fixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture());
            file = fullfile(fixture.Folder, "long-record.crg");

            data.struct = {repmat('A', 1, 90)};
            data.kd_def = {"channel one,m"};
            data.kd_dat = single((1:3).');

            testCase.verifyWarning(@() ipl_write(data, file, "LRFI"), "IPL:recLengthExceeded");
            lines = readlines(file, Encoding="ISO-8859-1");
            testCase.verifyLessThanOrEqual(strlength(lines(1)), 72);
        end

        function crgReadRepresentativeSamples(testCase, representativeFile)
            file = testCase.fullfileForCase(representativeFile);
            data = crg_read(file);

            testCase.verifyClass(data.z, "single");
            testCase.verifyGreaterThanOrEqual(size(data.z, 1), 2);
            testCase.verifyGreaterThanOrEqual(size(data.z, 2), 2);
        end

        function evaluationKernelsPreserveShapes(testCase)
            data = crg_read(fullfile(testCase.CrgBinaryFolder, "belgian_block.crg"));
            uValues = linspace(data.head.ubeg, data.head.uend, 25);
            vValues = linspace(data.head.vmin, data.head.vmax, 25);
            uvPoints = [uValues(:) vValues(:)];

            phi = crg_eval_u2phi(data, uValues);
            curvature = crg_eval_u2crv(data, uValues);
            [uIndices, vIndices] = crg_eval_uv2iuiv(data, uValues, vValues);
            zValues = crg_eval_uv2z(data, uvPoints);
            xyPoints = crg_eval_uv2xy(data, uvPoints);

            testCase.verifySize(phi, [1 25]);
            testCase.verifySize(curvature, [1 25]);
            testCase.verifySize(uIndices, [1 25]);
            testCase.verifySize(vIndices, [1 25]);
            testCase.verifySize(zValues, [25 1]);
            testCase.verifySize(xyPoints, [25 2]);
            testCase.verifyTrue(all(isfinite(xyPoints), "all"));
        end

        function uv2zVectorizedMatchesScalarCalls(testCase, representativeFile, borderCase)
            testCase.verifyUv2zScalarEquivalence(representativeFile, borderCase);
        end

        function crgIsequalIdentifiesSameData(testCase)
            data = crg_read(fullfile(testCase.CrgTextFolder, "handmade_curved.crg"));
            [isEqual, differenceData] = crg_isequal(data, data);

            testCase.verifyTrue(logical(isEqual));
            testCase.verifyEmpty(differenceData.err);
        end

        function crgIsequalDetectsGridChange(testCase)
            referenceData = crg_read(fullfile(testCase.CrgTextFolder, "handmade_curved.crg"));
            changedData = referenceData;
            changedData.z(1, 1) = changedData.z(1, 1) + single(0.1);

            [isEqual, differenceData] = crg_isequal(referenceData, changedData);

            testCase.verifyFalse(logical(isEqual));
            testCase.verifyGreaterThan(max(differenceData.mean(:)), 0);
        end

        function pxy2PpxyHandlesSplineBreakBoundaries(testCase)
            x = (0:0.1:4).';
            pxy = [x sin(x)];
            pxy = [pxy(1:11, :); pxy(11, :); pxy(12:end, :)];

            ppxy = crg_gen_pxy2ppxy(pxy, struct("sf_incr", 0.75, "ss_spar", 0.99));
            values = ppval(ppxy, ppxy.breaks);

            testCase.verifyEqual(ppxy.form, 'pp');
            testCase.verifyEqual(ppxy.pieces, numel(ppxy.breaks)-1);
            testCase.verifyTrue(all(isfinite(real(values)), "all"));
            testCase.verifyTrue(all(isfinite(imag(values)), "all"));
        end

        function showIsequalCreatesHistogramGraphic(testCase)
            data = crg_read(fullfile(testCase.CrgTextFolder, "handmade_curved.crg"));
            [~, differenceData] = crg_isequal(data, data);
            initialFigures = findall(groot, Type="figure");
            oldVisibility = get(groot, "DefaultFigureVisible");

            testCase.addTeardown(@() set(groot, "DefaultFigureVisible", oldVisibility));
            set(groot, "DefaultFigureVisible", "off");
            crg_show_isequal(differenceData);

            newFigures = setdiff(findall(groot, Type="figure"), initialFigures);
            testCase.addTeardown(@() close(newFigures));
            histogramObjects = findall(newFigures, Type="histogram");

            testCase.verifyNotEmpty(newFigures);
            testCase.verifyNotEmpty(histogramObjects);
        end

        function metricsSuiteRuns(testCase)
            results = opencrg_modernization_metrics();

            testCase.verifyGreaterThan(height(results), 3);
            testCase.verifyTrue(all(ismember( ...
                ["Metric", "Value", "Unit", "Notes"], string(results.Properties.VariableNames))));
        end
    end

    methods (Access = private)
        function file = fullfileForCase(testCase, representativeFile)
            switch representativeFile.Folder
                case "text"
                    folder = testCase.CrgTextFolder;
                case "binary"
                    folder = testCase.CrgBinaryFolder;
            end
            file = fullfile(folder, representativeFile.Name);
        end

        function verifyUv2zScalarEquivalence(testCase, representativeFile, borderCase)
            data = crg_read(testCase.fullfileForCase(representativeFile));
            uValues = linspace(data.head.ubeg - 2*data.head.uinc, data.head.uend + 2*data.head.uinc, 40).';
            vValues = linspace(data.head.vmin - 1, data.head.vmax + 1, 40).';
            uvPoints = [uValues vValues];
            data.opts.bdmu = borderCase.U;
            data.opts.bdmv = borderCase.V;

            vectorized = crg_eval_uv2z(data, uvPoints);
            scalar = arrayfun(@(rowIndex) crg_eval_uv2z(data, uvPoints(rowIndex, :)), (1:size(uvPoints, 1)).');
            finiteMask = isfinite(vectorized) & isfinite(scalar);

            testCase.verifyEqual(isnan(vectorized), isnan(scalar));
            testCase.verifyEqual(vectorized(finiteMask), scalar(finiteMask), AbsTol=1e-10);
        end
    end
end

function representativeFile = makeRepresentativeFiles()
representativeFile = struct( ...
    "handmadeCurved", struct("Folder", "text", "Name", "handmade_curved.crg"), ...
    "belgianBlock", struct("Folder", "binary", "Name", "belgian_block.crg"));
end

function borderCase = makeBorderCases()
borderCase = struct();
for borderModeU = 0:4
    for borderModeV = 0:4
        fieldName = sprintf("u%dv%d", borderModeU, borderModeV);
        borderCase.(fieldName) = struct("U", borderModeU, "V", borderModeV);
    end
end
end
