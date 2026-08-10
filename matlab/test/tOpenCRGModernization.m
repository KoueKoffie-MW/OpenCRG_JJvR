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

        function sdfCutPreservesBlockAndRemainder(testCase)
            source = {'keep before', '  $TARGET ! inline comment', 'value line', ...
                '$$escaped marker', '$END', 'keep after'};

            [block, remainder] = sdf_cut(source, 'target');

            testCase.verifyEqual(block, {'value line', '$escaped marker'});
            testCase.verifyEqual(remainder, {'keep before', 'keep after'});
        end

        function sdfAddEscapesNestedBlockMarkers(testCase)
            output = sdf_add({'before'}, 'TARGET', {'value', '$nested'});

            testCase.verifyEqual(output, {'before', '$TARGET', 'value', '$$nested', '$'});
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

        function numberedLongSectionsReadUniformLateralGrid(testCase)
            data = crg_read(fullfile(testCase.CrgBinaryFolder, "belgian_block.crg"));
            expectedColumnCount = round((data.head.vmax-data.head.vmin)/data.head.vinc) + 1;

            testCase.verifyEqual(size(data.z, 2), expectedColumnCount);
            testCase.verifyEqual(double(data.v), data.head.vmax, AbsTol=1e-6);
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

        function pxy2PpxyHandlesSparseNullSpaceBranch(testCase)
            x = linspace(0, 4, 2001).';
            pxy = [x sin(x)];

            ppxy = crg_gen_pxy2ppxy(pxy, struct("sf_incr", 0.05, "ss_spar", 0.99));
            values = ppval(ppxy, linspace(ppxy.breaks(1), ppxy.breaks(end), 100));

            testCase.verifyGreaterThan(ppxy.pieces, 60);
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

        function crgFlipRoundTripPreservesHeading(testCase)
            data = crg_read(fullfile(testCase.CrgTextFolder, "handmade_curved.crg"));
            flipped = crg_flip(data);
            restored = crg_flip(flipped);

            testCase.verifyEqual(flipped.p, angle(-exp(1i*data.p(end:-1:1))), AbsTol=single(1e-6));
            testCase.verifyEqual(restored.z, data.z);
            testCase.verifyEqual(restored.p, data.p, AbsTol=single(1e-6));
            testCase.verifyEqual(restored.head.pbeg, data.head.pbeg, AbsTol=1e-12);
            testCase.verifyEqual(restored.head.pend, data.head.pend, AbsTol=1e-12);
        end

        function wgs84DirectInverseRoundTrip(testCase)
            wgs1 = [51.477811 -0.001475; 48.8566 2.3522];
            wgs2 = [51.477678 0.000000; 48.8584 2.2945];

            [dist, dbeg, dend] = crg_wgs84_dist(wgs1, wgs2);
            [roundTrip, inverseDend] = crg_wgs84_invdist(wgs1, dbeg, dist);

            testCase.verifySize(dist, [1 2]);
            testCase.verifyTrue(all(isfinite(dist)));
            testCase.verifyTrue(all(dist > 0));
            testCase.verifyEqual(roundTrip, wgs2, AbsTol=1e-7);
            testCase.verifyEqual(angle(exp(1i*inverseDend)), angle(exp(1i*dend)), AbsTol=1e-10);
        end

        function wgsUrlSupportsMultiplePoints(testCase)
            url = crg_wgs84_wgs2url([51 9; 52 10], struct("label", "Open CRG"));

            testCase.verifyClass(url, "cell");
            testCase.verifyNumElements(url, 2);
            testCase.verifyTrue(contains(url{1}, "Open+CRG"));
        end

        function mapWgs2HtmlHandlesMultipleTracks(testCase)
            fixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture());
            file = fullfile(fixture.Folder, "tracks.html");
            tracks = {[51 9; 52 10]*pi/180, [48 8; 49 9]*pi/180};

            resultFile = map_wgs2html(tracks, file);

            testCase.verifyEqual(resultFile, file);
            testCase.verifyTrue(isfile(file));
            testCase.verifyTrue(contains(fileread(file), "Start 2"));
        end

        function mapLocalGlobalRoundTrip(testCase)
            llh = [deg2rad(48.8566) deg2rad(2.3522) 35; ...
                deg2rad(51.477811) deg2rad(-0.001475) 45];

            [enh, dat] = map_global2plocal(llh, 'UTM_31U');
            [roundTrip, dat] = map_plocal2global(enh, dat);

            testCase.verifySize(enh, size(llh));
            testCase.verifyEqual(roundTrip, llh, AbsTol=1e-10);
            testCase.verifyTrue(isfield(dat, "proj"));
        end

        function slopeAndBankingExtractionProduceFiniteProfiles(testCase)
            data = crg_read(fullfile(testCase.CrgTextFolder, "handmade_curved.crg"));

            slopeData = crg_ext_slope(data, 0.5);
            bankingData = crg_ext_banking(data, 0.5);

            testCase.verifyTrue(isfield(slopeData, "s"));
            testCase.verifyTrue(isfield(bankingData, "b"));
            testCase.verifyTrue(all(isfinite(slopeData.s)));
            testCase.verifyTrue(all(isfinite(bankingData.b)));
        end

        function derivativeFilterMasksRemainFinite(testCase)
            data = crg_read(fullfile(testCase.CrgTextFolder, "handmade_curved.crg"));
            filterMethods = {'sobel', '2diff', 'laplace'};

            for methodIndex = 1:numel(filterMethods)
                filtered = crg_filter(data, [], [], filterMethods{methodIndex}, [3 3], [1 1]);
                finiteValues = filtered.z(~isnan(filtered.z));

                testCase.verifySize(filtered.z, size(data.z));
                testCase.verifyTrue(all(isfinite(finiteValues)));
            end
        end

        function smoothFirfiltPreservesVectorOrientation(testCase)
            columnInput = (1:20).';
            rowInput = 1:20;

            columnOutput = smooth_firfilt(columnInput, 3);
            rowOutput = smooth_firfilt(rowInput, 3);

            testCase.verifySize(columnOutput, size(columnInput));
            testCase.verifySize(rowOutput, size(rowInput));
            testCase.verifyEqual(columnOutput.', rowOutput);
        end

        function crgCheckComputesNanEdgeBounds(testCase)
            data = crg_read(fullfile(testCase.CrgTextFolder, "handmade_curved.crg"));
            data.z(:, 1) = NaN;
            data.z(:, end) = NaN;
            data = rmfield(data, 'ok');

            checked = crg_check(data);

            testCase.verifyTrue(isfield(checked, "ok"));
            testCase.verifyEqual(checked.ir, 2*ones(1, size(data.z, 1)));
            testCase.verifyEqual(checked.il, (size(data.z, 2)-1)*ones(1, size(data.z, 1)));
        end

        function crgWriteRRHDExportsReadableMap(testCase)
            testCase.assumeTrue(exist("roadrunnerHDMap", "file") == 2, ...
                "RoadRunner HD Map API is unavailable.");
            fixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture());
            sourceFile = fullfile(testCase.CrgTextFolder, "handmade_curved.crg");
            rrhdFile = fullfile(fixture.Folder, "handmade_curved.rrhd");

            [rrMap, data, geometry] = crg_write_rrhd(sourceFile, rrhdFile, ...
                NumSamples=16, GeoReference=[51 9]);
            readBackMap = roadrunnerHDMap;
            read(readBackMap, rrhdFile);

            testCase.verifyTrue(isfile(rrhdFile));
            testCase.verifyNumElements(rrMap.Lanes, 1);
            testCase.verifyNumElements(rrMap.LaneBoundaries, 2);
            testCase.verifyEqual(rrMap.GeoReference, [51 9]);
            testCase.verifyNumElements(readBackMap.Lanes, 1);
            testCase.verifyNumElements(readBackMap.LaneBoundaries, 2);
            testCase.verifySize(rrMap.Lanes(1).Geometry, [16 3]);
            testCase.verifyEqual(geometry.CenterV, 0);
            testCase.verifyEqual(geometry.LaneVLimits, [data.head.vmin data.head.vmax]);
            testCase.verifyEqual(readBackMap.Lanes(1).ID, "Lane1");
        end

        function crgWriteRRHDSupportsMapOnlyCreation(testCase)
            testCase.assumeTrue(exist("roadrunnerHDMap", "file") == 2, ...
                "RoadRunner HD Map API is unavailable.");
            data = crg_read(fullfile(testCase.CrgTextFolder, "handmade_curved.crg"));

            [rrMap, ~, geometry] = crg_write_rrhd(data, Write=false, ...
                NumSamples=8, AddEdgeMarkings=false);

            testCase.verifyNumElements(rrMap.Lanes, 1);
            testCase.verifyEmpty(rrMap.LaneMarkings);
            testCase.verifySize(geometry.LeftBoundary, [8 3]);
            testCase.verifySize(geometry.RightBoundary, [8 3]);
        end

        function crgWriteRRHDExportsLateralStrips(testCase)
            testCase.assumeTrue(exist("roadrunnerHDMap", "file") == 2, ...
                "RoadRunner HD Map API is unavailable.");
            fixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture());
            sourceFile = fullfile(testCase.CrgTextFolder, "handmade_curved.crg");
            rrhdFile = fullfile(fixture.Folder, "handmade_curved_strips.rrhd");

            [rrMap, data, geometry] = crg_write_rrhd(sourceFile, rrhdFile, ...
                Mode="LateralStrips", NumSamples=12, GeoReference=[51 9]);
            readBackMap = roadrunnerHDMap;
            read(readBackMap, rrhdFile);
            lateralColumnCount = size(data.z, 2);

            testCase.verifyTrue(isfile(rrhdFile));
            testCase.verifyEqual(geometry.Mode, "LateralStrips");
            testCase.verifyNumElements(rrMap.Lanes, lateralColumnCount-1);
            testCase.verifyNumElements(rrMap.LaneBoundaries, lateralColumnCount);
            testCase.verifyNumElements(readBackMap.Lanes, lateralColumnCount-1);
            testCase.verifyNumElements(readBackMap.LaneBoundaries, lateralColumnCount);
            testCase.verifySize(rrMap.Lanes(1).Geometry, [12 3]);
            testCase.verifySize(rrMap.LaneBoundaries(1).Geometry, [12 3]);
            testCase.verifyNotEmpty(rrMap.LaneBoundaries(1).ParametricAttributes);
            testCase.verifyNotEmpty(rrMap.LaneBoundaries(end).ParametricAttributes);
            if lateralColumnCount > 2
                testCase.verifyEmpty(rrMap.LaneBoundaries(2).ParametricAttributes);
            end
        end

        function crgWriteRRHDSupportsStripMarkingModes(testCase)
            testCase.assumeTrue(exist("roadrunnerHDMap", "file") == 2, ...
                "RoadRunner HD Map API is unavailable.");
            data = crg_read(fullfile(testCase.CrgTextFolder, "handmade_curved.crg"));

            [rrMap, ~, geometry] = crg_write_rrhd(data, Write=false, ...
                Mode="LateralStrips", NumSamples=8, StripBoundaryMarkings="None", StripLaneType="Border");

            testCase.verifyEqual(geometry.Mode, "LateralStrips");
            testCase.verifyEmpty(rrMap.LaneMarkings);
            testCase.verifyEqual(string({rrMap.Lanes.LaneType}), repmat("Border", 1, numel(rrMap.Lanes)));
            for boundaryIndex = 1:numel(rrMap.LaneBoundaries)
                testCase.verifyEmpty(rrMap.LaneBoundaries(boundaryIndex).ParametricAttributes);
            end
        end

        function crgWriteSimscapeGridProducesVariables(testCase)
            fixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture());
            sourceFile = fullfile(testCase.CrgTextFolder, "handmade_curved.crg");
            matFile = fullfile(fixture.Folder, "handmade_curved_SimscapeGrid.mat");

            [x, y, z] = crg_write_simscape_grid(sourceFile, matFile, ...
                GridResolution=1, NumLongitudinalSamples=12, NumLateralSamples=7);
            loadedGrid = load(matFile);

            testCase.verifyTrue(isfile(matFile));
            testCase.verifyGreaterThan(numel(x), 1);
            testCase.verifyGreaterThan(numel(y), 1);
            testCase.verifySize(z, [numel(x) numel(y)]);
            testCase.verifyTrue(all(diff(x) > 0));
            testCase.verifyTrue(all(diff(y) > 0));
            testCase.verifyTrue(all(isfinite(z), "all"));
            testCase.verifyEqual(loadedGrid.x, x);
            testCase.verifyEqual(loadedGrid.y, y);
            testCase.verifyEqual(loadedGrid.z, z);
        end

        function crgWriteSimscapeGridSupportsSingleOutput(testCase)
            data = crg_read(fullfile(testCase.CrgTextFolder, "handmade_curved.crg"));

            [x, y, z] = crg_write_simscape_grid(data, Write=false, ...
                GridResolution=2, NumLongitudinalSamples=10, NumLateralSamples=5, OutputClass="single");

            testCase.verifyClass(x, "single");
            testCase.verifyClass(y, "single");
            testCase.verifyClass(z, "single");
            testCase.verifySize(z, [numel(x) numel(y)]);
        end

        function crgWriteSimscapeGridFeedsGridSurfaceMask(testCase)
            testCase.assumeTrue(exist("load_system", "file") == 2 && ~isempty(which("sm_lib")), ...
                "Simscape Multibody library is unavailable.");
            data = crg_read(fullfile(testCase.CrgTextFolder, "handmade_curved.crg"));
            [x, y, z] = crg_write_simscape_grid(data, Write=false, ...
                GridResolution=2, NumLongitudinalSamples=8, NumLateralSamples=5);
            modelName = "opencrgGridSurface" + string(randi(1e9));
            new_system(modelName);
            testCase.addTeardown(@() close_system(modelName, 0));
            load_system("sm_lib");
            blockPath = modelName + "/Grid Surface";
            add_block("sm_lib/Curves and Surfaces/Grid Surface", blockPath);
            modelWorkspace = get_param(modelName, "ModelWorkspace");
            assignin(modelWorkspace, "gridX", x);
            assignin(modelWorkspace, "gridY", y);
            assignin(modelWorkspace, "gridZ", z);

            set_param(blockPath, XGridVector="gridX", YGridVector="gridY", ZHeights="gridZ");

            set_param(modelName, "SimulationCommand", "Update");
        end

        function crgExportLookupWritesElevationTable(testCase)
            fixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture());
            sourceFile = fullfile(testCase.CrgTextFolder, "handmade_curved.crg");
            matFile = fullfile(fixture.Folder, "handmade_curved_Lookup.mat");

            [lookup, data] = crg_export_lookup(sourceFile, matFile, ...
                Channel="Elevation", CreateSimulinkLookupTable=false);
            loadedLookup = load(matFile);

            testCase.verifyTrue(isfile(matFile));
            testCase.verifyEqual(lookup.Channel, "Elevation");
            testCase.verifyEqual(lookup.TableUnit, "m");
            testCase.verifyEqual(lookup.Breakpoints1, data.u);
            testCase.verifyEqual(lookup.Breakpoints2, data.v);
            testCase.verifyEqual(lookup.Table, data.z);
            testCase.verifyEqual(loadedLookup.u, lookup.Breakpoints1);
            testCase.verifyEqual(loadedLookup.v, lookup.Breakpoints2);
            testCase.verifyEqual(loadedLookup.tableData, lookup.Table);
            testCase.verifyEqual(loadedLookup.lookup.TableUnit, "m");
        end

        function crgExportLookupReadsFrictionUnit(testCase)
            fixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture());
            sourceFile = fullfile(testCase.CrgTextFolder, "handmade_curved.crg");
            frictionFile = fullfile(fixture.Folder, "handmade_friction.crg");
            lines = readlines(sourceFile, Encoding="ISO-8859-1");
            longSectionRows = contains(lines, "D:long section");
            lines(longSectionRows) = regexprep(lines(longSectionRows), ',m(\s*(!.*)?)$', ',1$1');
            writelines(lines, frictionFile, Encoding="ISO-8859-1");

            lookup = crg_export_lookup(frictionFile, Write=false, ...
                Channel="Friction", ChannelUnit="1", CreateSimulinkLookupTable=false);

            testCase.verifyEqual(lookup.Channel, "Friction");
            testCase.verifyEqual(lookup.TableUnit, "1");
            testCase.verifySize(lookup.Table, [23 7]);
            testCase.verifyEqual(lookup.Breakpoints2, [-1.5 -1.25 -1 0 1 1.25 1.5]);
        end

        function crgExportLookupCreatesSimulinkObject(testCase)
            testCase.assumeTrue(exist("Simulink.LookupTable", "class") == 8, ...
                "Simulink.LookupTable is unavailable.");
            data = crg_read(fullfile(testCase.CrgTextFolder, "handmade_curved.crg"));

            lookup = crg_export_lookup(data, Write=false, Channel="Elevation");

            testCase.verifyTrue(isfield(lookup, "SimulinkLookupTable"));
            testCase.verifyClass(lookup.SimulinkLookupTable, "Simulink.LookupTable");
            testCase.verifyEqual(lookup.SimulinkLookupTable.Table.Value, lookup.Table);
            testCase.verifyEqual(lookup.SimulinkLookupTable.Breakpoints(1).Value, lookup.Breakpoints1);
            testCase.verifyEqual(lookup.SimulinkLookupTable.Breakpoints(2).Value, lookup.Breakpoints2);
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
