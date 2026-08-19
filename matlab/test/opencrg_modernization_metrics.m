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

    simscapeGridTime = timeit(@() crg_write_simscape_grid(data, Write=false, ...
        GridResolution=1, NumLongitudinalSamples=50, NumLateralSamples=7));
    [metricNames, metricValues, metricUnits, metricNotes] = addMetric( ...
        metricNames, metricValues, metricUnits, metricNotes, ...
        "crg_write_simscape_grid.mapOnly", simscapeGridTime, "seconds", ...
        "Simscape Grid Surface variable creation");

    lookupTime = timeit(@() crg_export_lookup(data, Write=false, CreateSimulinkLookupTable=false));
    [metricNames, metricValues, metricUnits, metricNotes] = addMetric( ...
        metricNames, metricValues, metricUnits, metricNotes, ...
        "crg_export_lookup.mapOnly", lookupTime, "seconds", ...
        "Lookup table struct creation");

    tireLookupTime = timeit(@() crg_export_tire_plane_lookup(data, Write=false, Precision="single"));
    [road, tireLookupMetadata] = crg_export_tire_plane_lookup(data, Write=false, Precision="single");
    puvLookup = representativePuv(data, 1000);
    pxyLookup = crg_eval_uv2xy(data, puvLookup);
    tireLookupStepTime = timeit(@() crgTirePlaneLookupStepLoop(road, pxyLookup));
    roadSurface = road;
    roadSurface.hasFriction = 1.0;
    roadSurface.hasNormals = 1.0;
    roadSurface.friction = single(0.8*ones(size(roadSurface.z)));
    roadSurface.normalX = single(zeros(size(roadSurface.z)));
    roadSurface.normalY = single(zeros(size(roadSurface.z)));
    roadSurface.normalZ = single(ones(size(roadSurface.z)));
    roadSurfaceStepTime = timeit(@() crgRoadSurfaceLookupStepLoop(roadSurface, pxyLookup));
    roadSurfaceInfo = whos("roadSurface");
    [metricNames, metricValues, metricUnits, metricNotes] = addMetric( ...
        metricNames, metricValues, metricUnits, metricNotes, ...
        "crg_export_tire_plane_lookup.single", tireLookupTime, "seconds", ...
        "CRG-native tire-plane lookup export");
    [metricNames, metricValues, metricUnits, metricNotes] = addMetric( ...
        metricNames, metricValues, metricUnits, metricNotes, ...
        "crg_tire_plane_lookup_step.1k", tireLookupStepTime, "seconds", ...
        "Codegen-safe tire-plane lookup loop with 1000 x/y queries");
    [metricNames, metricValues, metricUnits, metricNotes] = addMetric( ...
        metricNames, metricValues, metricUnits, metricNotes, ...
        "crg_tire_plane_lookup.bytes", tireLookupMetadata.ApproxBytes, "bytes", ...
        "Approximate lookup road struct memory");
    [metricNames, metricValues, metricUnits, metricNotes] = addMetric( ...
        metricNames, metricValues, metricUnits, metricNotes, ...
        "crg_road_surface_lookup_step.1k", roadSurfaceStepTime, "seconds", ...
        "Height, friction, and normal lookup loop with 1000 x/y queries");
    [metricNames, metricValues, metricUnits, metricNotes] = addMetric( ...
        metricNames, metricValues, metricUnits, metricNotes, ...
        "crg_road_surface_lookup.bytes", roadSurfaceInfo.bytes, "bytes", ...
        "MATLAB road-surface struct memory for the sample CRG");
end

if ~isempty(fixtures) && ~isempty(mex.getCompilerConfigurations("C", "Selected"))
    try
        buildInfo = crg_build_simulink_runtime(Target="mex", Verbose=false);
        addpath(buildInfo.OutputFolder);
        data = crg_read(fixtures(end).File);
        puv = representativePuv(data, 1000);
        pxy = crg_eval_uv2xy(data, puv);
        runtimeHandle = crg_runtime_mex("open", fixtures(end).File, 50);
        cleanupRuntime = onCleanup(@() crg_runtime_mex("close", runtimeHandle));
        runtimeTime = timeit(@() crgRuntimeMexStepLoop(runtimeHandle, pxy));
        planeTime = timeit(@() crgRuntimeMexPlaneLoop(runtimeHandle, pxy));
        clear cleanupRuntime
        [metricNames, metricValues, metricUnits, metricNotes] = addMetric( ...
            metricNames, metricValues, metricUnits, metricNotes, ...
            "crg_runtime_mex.xy2z.1k", runtimeTime, "seconds", ...
            "C API scalar runtime loop with 1000 x/y queries");
        [metricNames, metricValues, metricUnits, metricNotes] = addMetric( ...
            metricNames, metricValues, metricUnits, metricNotes, ...
            "crg_runtime_mex.tirePlane.1k", planeTime, "seconds", ...
            "Drop-in tire-plane runtime loop with 1000 x/y queries");
    catch err
        [metricNames, metricValues, metricUnits, metricNotes] = addMetric( ...
            metricNames, metricValues, metricUnits, metricNotes, ...
            "crg_runtime_mex.xy2z.available", 0, "logical", string(err.message));
    end
end

if ~isempty(fixtures)
    data = crg_read(fixtures(1).File);
    meshTime = timeit(@() crg_export_mesh(data, ...
        NumLongitudinalSamples=50, NumLateralSamples=7, PhysicsMesh=true));
    mesh = crg_export_mesh(data, NumLongitudinalSamples=50, NumLateralSamples=7, PhysicsMesh=true);
    [metricNames, metricValues, metricUnits, metricNotes] = addMetric( ...
        metricNames, metricValues, metricUnits, metricNotes, ...
        "crg_export_mesh.physics.50x7", meshTime, "seconds", ...
        "Physics mesh variable creation");
    [metricNames, metricValues, metricUnits, metricNotes] = addMetric( ...
        metricNames, metricValues, metricUnits, metricNotes, ...
        "crg_export_mesh.vertices.50x7", size(mesh.Vertices, 1), "count", ...
        "Physics mesh vertex count");
    [metricNames, metricValues, metricUnits, metricNotes] = addMetric( ...
        metricNames, metricValues, metricUnits, metricNotes, ...
        "crg_export_mesh.faces.50x7", size(mesh.Faces, 1), "count", ...
        "Physics mesh face count");

    blenderExecutable = opencrgFindBlenderExecutable();
    if blenderExecutable ~= ""
        fbxFile = fullfile(tempdir, "opencrg_metrics_mesh.fbx");
        fbxTime = timeit(@() crg_write_fbx(data, fbxFile, BlenderExecutable=blenderExecutable, ...
            NumLongitudinalSamples=20, NumLateralSamples=5, PhysicsMesh=true));
        fileInfo = dir(fbxFile);
        [metricNames, metricValues, metricUnits, metricNotes] = addMetric( ...
            metricNames, metricValues, metricUnits, metricNotes, ...
            "crg_write_fbx.physics.20x5", fbxTime, "seconds", ...
            "Blender-backed FBX export");
        [metricNames, metricValues, metricUnits, metricNotes] = addMetric( ...
            metricNames, metricValues, metricUnits, metricNotes, ...
            "crg_write_fbx.bytes.20x5", fileInfo.bytes, "bytes", ...
            "FBX file size");
        if isfile(fbxFile)
            delete(fbxFile);
        end
    end
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

function crgTirePlaneLookupStepLoop(road, pxy)
iuPrevious = 1.0;
pzPrevious = 0.0;
xPrevious = pxy(1, 1);
yPrevious = pxy(1, 2);
for pointIndex = 1:size(pxy, 1)
    [~, ~, pzPrevious, iuPrevious] = crg_tire_plane_lookup_step( ...
        pxy(pointIndex, 1), pxy(pointIndex, 2), pzPrevious, xPrevious, yPrevious, iuPrevious, road);
    xPrevious = pxy(pointIndex, 1);
    yPrevious = pxy(pointIndex, 2);
end
end

function crgRoadSurfaceLookupStepLoop(road, pxy)
iuPrevious = 1.0;
pzPrevious = 0.0;
xPrevious = pxy(1, 1);
yPrevious = pxy(1, 2);
for pointIndex = 1:size(pxy, 1)
    [~, ~, pzPrevious, iuPrevious] = crg_road_surface_lookup_step( ...
        pxy(pointIndex, 1), pxy(pointIndex, 2), pzPrevious, xPrevious, yPrevious, iuPrevious, road);
    xPrevious = pxy(pointIndex, 1);
    yPrevious = pxy(pointIndex, 2);
end
end

function crgRuntimeMexStepLoop(runtimeHandle, pxy)
for pointIndex = 1:size(pxy, 1)
    [~, ~, ~, ~, ~, status] = crg_runtime_mex("step", ...
        runtimeHandle, pxy(pointIndex, 1), pxy(pointIndex, 2), false);
    if status ~= 0
        error("CRG:runtimeError", "OpenCRG C runtime returned status %g.", status)
    end
end
end

function crgRuntimeMexPlaneLoop(runtimeHandle, pxy)
for pointIndex = 1:size(pxy, 1)
    [~, ~, ~, ~, ~, ~, ~, status] = crg_runtime_mex("plane", ...
        runtimeHandle, pxy(pointIndex, 1), pxy(pointIndex, 2), false);
    if status ~= 0
        error("CRG:runtimeError", "OpenCRG tire-plane runtime returned status %g.", status)
    end
end
end

function blenderExecutable = opencrgFindBlenderExecutable()
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

function [names, values, units, notes] = addMetric(names, values, units, notes, name, value, unit, note)
names(end+1, 1) = name;
values(end+1, 1) = value;
units(end+1, 1) = unit;
notes(end+1, 1) = note;
end
