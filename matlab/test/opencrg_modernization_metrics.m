function results = opencrg_modernization_metrics(options)
%OPENCRG_MODERNIZATION_METRICS Collect repeatable modernization metrics.
%   RESULTS = OPENCRG_MODERNIZATION_METRICS collects timing, Code Analyzer,
%   and representative data-shape metrics for the OpenCRG MATLAB code.

arguments
    options.OutputFile (1, 1) string = ""
    options.IncludeLargeFiles (1, 1) logical = false
end

paths = opencrgMetricPaths();
fixtures = opencrgLoadFixtures(paths, options.IncludeLargeFiles);

metricNames = strings(0, 1);
metricValues = zeros(0, 1);
metricUnits = strings(0, 1);
metricNotes = strings(0, 1);

[metricNames, metricValues, metricUnits, metricNotes] = addMetric( ...
    metricNames, metricValues, metricUnits, metricNotes, ...
    "codeIssues.total", countCodeIssues(paths.Matlab), "count", "All severities under matlab");
[metricNames, metricValues, metricUnits, metricNotes] = addMetric( ...
    metricNames, metricValues, metricUnits, metricNotes, ...
    "codeIssues.warning", countCodeIssues(paths.Matlab, "warning"), "count", "Warnings under matlab");

for k = 1:numel(fixtures)
    fixture = fixtures(k);
    readTime = timeit(@() crg_read(fixture.File));
    [metricNames, metricValues, metricUnits, metricNotes] = addMetric( ...
        metricNames, metricValues, metricUnits, metricNotes, ...
        "crg_read." + fixture.Name, readTime, "seconds", fixture.File);

    data = crg_read(fixture.File);
    [metricNames, metricValues, metricUnits, metricNotes] = addMetric( ...
        metricNames, metricValues, metricUnits, metricNotes, ...
        "data.z.rows." + fixture.Name, size(data.z, 1), "count", "Elevation grid rows");
    [metricNames, metricValues, metricUnits, metricNotes] = addMetric( ...
        metricNames, metricValues, metricUnits, metricNotes, ...
        "data.z.columns." + fixture.Name, size(data.z, 2), "count", "Elevation grid columns");
end

if ~isempty(fixtures)
    data = crg_read(fixtures(end).File);
    puv = representativePuv(data, 10000);
    [metricNames, metricValues, metricUnits, metricNotes] = addMetric( ...
        metricNames, metricValues, metricUnits, metricNotes, ...
        "crg_eval_uv2z.10k", timeit(@() crg_eval_uv2z(data, puv)), "seconds", fixtures(end).Name);
    [metricNames, metricValues, metricUnits, metricNotes] = addMetric( ...
        metricNames, metricValues, metricUnits, metricNotes, ...
        "crg_eval_uv2xy.10k", timeit(@() crg_eval_uv2xy(data, puv)), "seconds", fixtures(end).Name);
    pxy = crg_eval_uv2xy(data, puv(1:min(1000, size(puv, 1)), :));
    [metricNames, metricValues, metricUnits, metricNotes] = addMetric( ...
        metricNames, metricValues, metricUnits, metricNotes, ...
        "crg_eval_xy2uv.1k", timeit(@() crg_eval_xy2uv(data, pxy)), "seconds", fixtures(end).Name);

    puv = representativePuv(data, 100000);
    [metricNames, metricValues, metricUnits, metricNotes] = addMetric( ...
        metricNames, metricValues, metricUnits, metricNotes, ...
        "crg_eval_uv2z.100k", timeit(@() crg_eval_uv2z(data, puv)), "seconds", fixtures(end).Name);
end

if exist("roadrunnerHDMap", "file") == 2 && ~isempty(fixtures)
    data = crg_read(fixtures(1).File);
    rrhdSampleCount = min(100, size(data.z, 1));
    rrhdTime = timeit(@() crg_write_rrhd(data, Write=false, ...
        NumSamples=rrhdSampleCount, AddEdgeMarkings=false));
    [metricNames, metricValues, metricUnits, metricNotes] = addMetric( ...
        metricNames, metricValues, metricUnits, metricNotes, ...
        "crg_write_rrhd.mapOnly", rrhdTime, "seconds", ...
        "RoadRunner HD Map object creation with " + rrhdSampleCount + " samples");

    rrhdStripSampleCount = min(50, size(data.z, 1));
    rrhdStripTime = timeit(@() crg_write_rrhd(data, Write=false, ...
        Mode="LateralStrips", NumSamples=rrhdStripSampleCount, StripBoundaryMarkings="None"));
    [metricNames, metricValues, metricUnits, metricNotes] = addMetric( ...
        metricNames, metricValues, metricUnits, metricNotes, ...
        "crg_write_rrhd.lateralStrips.mapOnly", rrhdStripTime, "seconds", ...
        "RoadRunner strip HD Map object creation with " + rrhdStripSampleCount + " samples");
end

results = table(metricNames, metricValues, metricUnits, metricNotes, ...
    VariableNames=["Metric", "Value", "Unit", "Notes"]);

if options.OutputFile ~= ""
    writetable(results, options.OutputFile);
end
end

function paths = opencrgMetricPaths()
testFolder = string(fileparts(mfilename("fullpath")));
paths.Matlab = fileparts(testFolder);
paths.Repository = fileparts(paths.Matlab);
paths.CrgText = fullfile(paths.Repository, "crg-txt");
paths.CrgBinary = fullfile(paths.Repository, "crg-bin");
end

function fixtures = opencrgLoadFixtures(paths, includeLargeFiles)
fixtures = struct("Name", {}, "File", {});
fixtures(end+1) = struct("Name", "handmade_curved", ...
    "File", fullfile(paths.CrgText, "handmade_curved.crg"));
fixtures(end+1) = struct("Name", "belgian_block", ...
    "File", fullfile(paths.CrgBinary, "belgian_block.crg"));
if includeLargeFiles
    fixtures(end+1) = struct("Name", "country_road", ...
        "File", fullfile(paths.CrgBinary, "country_road.crg"));
end
end

function count = countCodeIssues(matlabFolder, severity)
arguments
    matlabFolder (1, 1) string
    severity (1, 1) string = ""
end

issues = codeIssues(matlabFolder);
if isempty(issues.Issues)
    count = 0;
    return
end

if severity == ""
    count = height(issues.Issues);
else
    count = nnz(string(issues.Issues.Severity) == severity);
end
end

function puv = representativePuv(data, pointCount)
rng("default");
pu = linspace(data.head.ubeg, data.head.uend, pointCount).';
pv = data.head.vmin + (data.head.vmax-data.head.vmin)*rand(pointCount, 1);
puv = [pu pv];
end

function [names, values, units, notes] = addMetric(names, values, units, notes, name, value, unit, note)
names(end+1, 1) = name;
values(end+1, 1) = value;
units(end+1, 1) = unit;
notes(end+1, 1) = note;
end
