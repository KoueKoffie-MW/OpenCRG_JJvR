# OpenCRG JJvR MATLAB Extensions

This fork keeps the upstream ASAM OpenCRG layout and adds MATLAB-focused modernization work plus exporters for MathWorks simulation workflows.

## What This Fork Adds

- Faster MATLAB parsing/evaluation paths with Code Analyzer debt kept at zero.
- `crg_write_rrhd` for RoadRunner HD Map (`.rrhd`) export.
- `crg_write_rrhd(..., Mode="LateralStrips")` for higher-fidelity CRG surface representation using many thin RRHD lanes.
- `crg_write_simscape_grid` for Simscape Multibody Grid Surface variables.
- `crg_export_lookup` for Simulink-compatible lookup-table variables.
- `crg_sfun_xy2z` and `crg_runtime_xy2z_file` for C API backed scalar Simulink queries.
- Regression and metrics coverage in `matlab/test/tOpenCRGModernization.m` and `matlab/test/opencrg_modernization_metrics.m`.

## Setup

```matlab
repo = "C:\GIT2026\OpenCRG";
addpath(genpath(fullfile(repo, "matlab")));
```

The RRHD exporter requires the RoadRunner HD Map API (`roadrunnerHDMap`). The Simscape Grid Surface exporter returns plain MATLAB variables and can optionally be used with the Simscape Multibody Grid Surface block.

## RoadRunner HD Map Export

Single-lane export:

```matlab
crgFile = fullfile(repo, "crg-txt", "handmade_curved.crg");
rrhdFile = fullfile(tempdir, "handmade_curved_single_lane.rrhd");

rrMap = crg_write_rrhd(crgFile, rrhdFile, NumSamples=100);
```

Lateral-strip export:

```matlab
stripFile = fullfile(tempdir, "handmade_curved_lateral_strips.rrhd");

stripMap = crg_write_rrhd(crgFile, stripFile, ...
    Mode="LateralStrips", ...
    StripLaneType="Driving", ...
    StripBoundaryMarkings="OuterOnly");
```

`Mode="LateralStrips"` creates one shared RRHD lane boundary per selected CRG lateral grid column and one thin lane between adjacent columns. This preserves the CRG surface profile better than the default single-lane export, but it is a geometry-fidelity workaround: RoadRunner will still see many lane entities.

Useful RRHD options:

- `NumSamples`: longitudinal samples; default uses the CRG row count.
- `LaneVLimits`: export a lateral subset.
- `GeoReference`: set `[latitude longitude]`.
- `StripLaneType`: lane type for strip lanes; default `"Driving"`.
- `StripBoundaryMarkings`: `"None"`, `"OuterOnly"` default, or `"All"`.
- `EvalChunkSize`: limits temporary UV evaluation batches for large CRGs.

Run the demo:

```matlab
run(fullfile(repo, "matlab", "demo", "crg_demo_write_rrhd.m"));
```

## Simscape Grid Surface Export

Export variables for the Simscape Multibody Grid Surface block:

```matlab
gridFile = fullfile(tempdir, "handmade_curved_SimscapeGrid.mat");

[x, y, z] = crg_write_simscape_grid(crgFile, gridFile, GridResolution=0.5);
```

Use these Grid Surface mask parameters:

- `XGridVector`: `x`
- `YGridVector`: `y`
- `ZHeights`: `z`
- Units: `m`

The function samples CRG `u/v/z`, maps points to local `x/y/z`, then interpolates onto a regular `x/y` grid. `z` is sized `[numel(x) numel(y)]`, matching Grid Surface usage.

Useful Simscape options:

- `GridResolution`: regular output grid spacing in meters.
- `NumLongitudinalSamples`: longitudinal CRG samples; default uses CRG rows.
- `NumLateralSamples`: lateral CRG samples; default uses CRG columns.
- `LaneVLimits`: export a lateral subset.
- `InterpolationMethod`: `"linear"` default, `"nearest"`, or `"natural"`.
- `ExtrapolationMethod`: `"nearest"` default, `"linear"`, or `"none"`.
- `OutputClass`: `"double"` default or `"single"`.

Run the demo:

```matlab
run(fullfile(repo, "matlab", "demo", "crg_demo_write_simscape_grid.m"));
```

## Lookup-Table Export

Export CRG data as lookup-table breakpoints and table data:

```matlab
lookupFile = fullfile(tempdir, "handmade_curved_Lookup.mat");

lookup = crg_export_lookup(crgFile, lookupFile, Channel="Elevation");
```

The saved MAT-file contains:

- `u`: longitudinal breakpoints in meters.
- `v`: lateral breakpoints in meters.
- `tableData`: table values sized `[numel(u) numel(v)]`.
- `lookup`: metadata struct with units and source information.
- `simulinkLookupTable`: `Simulink.LookupTable` object when Simulink is available.

This format is useful for Simulink lookup blocks, calibration data, controller logic, tire models, and road-property maps. The exporter can also read CRG files whose long-section channels are not elevation data. For friction coefficient data stored with unit `1`, use:

```matlab
muLookup = crg_export_lookup("friction_map.crg", ...
    Channel="Friction", ...
    ChannelUnit="1");
```

Useful lookup options:

- `Channel`: label such as `"Elevation"` or `"Friction"`.
- `ChannelUnit`: CRG long-section unit to select; use `"m"` for elevation or `"1"` for friction coefficient.
- `OutputClass`: `"double"` default or `"single"`.
- `CreateSimulinkLookupTable`: create a `Simulink.LookupTable` object.

Run the demo:

```matlab
run(fullfile(repo, "matlab", "demo", "crg_demo_export_lookup.m"));
```

## Simulink C Runtime

Build the C API backed runtime wrappers:

```matlab
buildInfo = crg_build_simulink_runtime(Target="all");
addpath(buildInfo.OutputFolder);
```

Export Simulink runtime metadata and lookup fallback variables:

```matlab
runtimeFile = fullfile(tempdir, "handmade_curved_SimulinkRuntime.mat");
runtime = crg_export_simulink_runtime(crgFile, runtimeFile);
```

The runtime supports scalar streaming queries where one `x,y` pair is evaluated per timestep. The C path uses the OpenCRG contact-point API for `xy2uv`, `uv2z`, heading and curvature, so it preserves the C API evaluation semantics for elevation and geometry.

Use the MEX runtime directly:

```matlab
runtimeHandle = crg_runtime_mex("open", crgFile, runtime.HistorySize);
cleanupRuntime = onCleanup(@() crg_runtime_mex("close", runtimeHandle));

[u, v, z, phi, curvature, status] = crg_runtime_mex("step", ...
    runtimeHandle, x, y, false);
```

Use the S-Function block with:

- Function name: `crg_sfun_xy2z`
- Parameters: `'<path-to-road.crg>', 50`
- Inputs: scalar `x`, scalar `y`, scalar `reset`
- Outputs: `u`, `v`, `z`, `phi`, `curvature`, `status`

The code-generation helper `crg_runtime_xy2z_file` uses `coder.ceval` to call the same C runtime from generated MATLAB code. File-backed generated code expects filesystem access to the CRG file. Embedded-array deployment remains represented by the exported lookup variables and is the next backend-hardening step for targets without runtime file access.

Run the demo:

```matlab
run(fullfile(repo, "matlab", "demo", "crg_demo_simulink_runtime.m"));
```

## Metrics And Validation

Collect modernization metrics:

```matlab
results = opencrg_modernization_metrics();
disp(results);
```

The metrics include Code Analyzer issue counts, representative read/evaluation timings, RRHD object creation timings, Simscape Grid Surface variable creation timing, lookup export timing, and C runtime scalar-loop timing when a C MEX compiler is configured.

Run the MATLAB modernization regression suite:

```matlab
results = runtests(fullfile(repo, "matlab", "test", "tOpenCRGModernization.m"));
assert(all([results.Passed]));
```

Current representative metrics show:

- Code Analyzer issues: `0`
- Code Analyzer warnings: `0`
- `crg_read.belgian_block`: about `0.02 s`
- `crg_eval_uv2z.100k`: about `0.002 s`
- RRHD map-only export: low milliseconds for representative samples
- Simscape Grid Surface variable creation: low milliseconds for representative samples
- Lookup table struct creation: low milliseconds for representative samples

Timings are machine- and release-dependent; use `opencrg_modernization_metrics` for the source of truth on your system.
