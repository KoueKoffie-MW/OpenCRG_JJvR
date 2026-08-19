# OpenCRG JJvR MATLAB Extensions

This fork keeps the upstream ASAM OpenCRG layout and adds MATLAB-focused modernization work plus exporters for MathWorks simulation workflows.

## What This Fork Adds

- Faster MATLAB parsing/evaluation paths with Code Analyzer debt kept at zero.
- `crg_write_rrhd` for RoadRunner HD Map (`.rrhd`) export.
- `crg_write_rrhd(..., Mode="LateralStrips")` for higher-fidelity CRG surface representation using many thin RRHD lanes.
- `crg_write_simscape_grid` for Simscape Multibody Grid Surface variables.
- `crg_export_lookup` for Simulink-compatible lookup-table variables.
- `crg_export_road_surface_lookup` and `crg_road_surface_lookup_step` for codegen-safe per-tire Simulink road queries with friction and normal CRGs.
- `crg_sfun_xy2z`, `crg_sfun_tire_plane`, and `crg_runtime_xy2z_file` for experimental C API backed scalar Simulink queries.`r`n- `crg_export_mesh`, `crg_write_fbx`, and `crg_create_sim3d_actor` for Unreal/Simulink 3D road meshes.
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

## Tire-Plane Lookup For Simulink

For multi-tire vehicle models, prefer the CRG-native lookup path over S-Functions. It stores the road in compact `u/v` coordinates and avoids runtime CRG file I/O, native global state, and large winding-road `x/y` grids.

Export a road lookup MAT-file once:

```matlab
[road, metadata] = crg_export_tire_plane_lookup(crgFile, "road_TirePlaneLookup.mat", ...
    Precision="single", ...
    LocalSearchRadius=25, ...
    CoarseSearchStride=25);
```

Use one MATLAB Function block per tire with `road` as a block/model parameter and this body:

```matlab
function [px, py, pz, iu_curr, qx, qy, qz] = fcn(x, y, pz_prev, x_prev, y_prev, iu_prev)
%#codegen
[px, py, pz, iu_curr, qx, qy, qz] = crg_tire_plane_lookup_step( ...
    x, y, pz_prev, x_prev, y_prev, iu_prev, road);
end
```

The runtime first searches near `iu_prev`, then falls back to a coarse reference-line search if the local projection is too far away. If the tire is outside the CRG `u/v` domain or receives invalid `x/y`, it returns `pz_prev` and `iu_prev` instead of crashing or extrapolating.

Memory is approximately the original CRG `z` table plus a few 1-D vectors. Use `Precision="single"` for model deployment unless you need double-precision road heights.
## Matched Road-Surface Lookup

If your delivery contains a matched 5-file CRG set, prefer the road-surface lookup exporter. Starting from `*_road.crg`, it auto-discovers `*_friction.crg`, `*_nx.crg`, `*_ny.crg`, and `*_nz.crg` in the same folder.

```matlab
[road, metadata] = crg_export_road_surface_lookup("scenario_road.crg", ...
    Precision="single", ...
    RequireMatchedFiles=true);
```

Use one MATLAB Function block per tire with `road` as a block/model parameter:

```matlab
function [px, py, pz, iu_curr, qx, qy, qz, mu] = fcn(x, y, pz_prev, x_prev, y_prev, iu_prev)
%#codegen
[px, py, pz, iu_curr, qx, qy, qz, mu] = crg_road_surface_lookup_step( ...
    x, y, pz_prev, x_prev, y_prev, iu_prev, road);
end
```

`pz` comes from the road-height CRG, `mu` from the friction CRG, and `qx/qy` are computed from the pre-exported normal vector expressed in the local road-heading frame. If normal CRGs are missing, the runtime falls back to smooth `slope/bank/phi` orientation.
## Experimental Simulink C Runtime

Build the C API backed runtime wrappers only for single-instance experiments or offline reference checks:

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

Experimental legacy tire-plane S-Function drop-in block:

- Function name: `crg_sfun_tire_plane`
- Parameters: `'<path-to-road.crg>', 50`
- Inputs: scalar `x`, `y`, `pz_prev`, `x_prev`, `y_prev`, `iu_prev`
- Outputs: `px`, `py`, `pz`, `iu_curr`, `qx`, `qy`, `qz`

`crg_sfun_tire_plane` is not recommended for multi-tire production vehicle models because the OpenCRG C API uses native global state. Prefer the lookup path above. It was intended to replace the older MATLAB Function block pattern that called `crg_eval_xy2uv_codegen` and `crg_eval_uv2z_codegen` per tire. It keeps one C contact point/history per block instance, uses the OpenCRG C API for `x/y -> u/v/z`, and computes smooth tire-plane orientation from reference-line slope and bank: `qx = atan(bank(u))`, `qy = -atan(slope(u))`, `qz = phi(u)`. The previous-value inputs are accepted for wiring compatibility and fallback behavior, but the C runtime owns the actual search history.

For a model-level drop-in subsystem with the same six numeric inputs and seven outputs as the legacy block, use:

```matlab
crg_add_tire_plane_block("myModel/OpenCRGTirePlane", crgFile, HistorySize=50);
```

To replace an already connected legacy block and preserve the first six input lines plus all seven output lines, use:

```matlab
crg_replace_tire_plane_block("myModel/LegacyTirePlaneFcn", crgFile, HistorySize=50);
```

If the old block exposed `crg` as a seventh signal input, that wire is intentionally removed: the C runtime now receives the CRG road through the S-Function file parameter.

The code-generation helper `crg_runtime_xy2z_file` uses `coder.ceval` to call the same C runtime from generated MATLAB code. File-backed generated code expects filesystem access to the CRG file. Embedded-array deployment remains represented by the exported lookup variables and is the next backend-hardening step for targets without runtime file access.

Run the demo:

```matlab
run(fullfile(repo, "matlab", "demo", "crg_demo_simulink_runtime.m"));
```

## FBX And Simulink 3D Mesh Export

Create a reusable physics-oriented CRG road mesh:

```matlab
mesh = crg_export_mesh(crgFile, ...
    NumLongitudinalSamples=100, ...
    NumLateralSamples=11, ...
    PhysicsMesh=true, ...
    Thickness=0.05);
```

Write the mesh as FBX using Blender in headless mode:

```matlab
fbxFile = fullfile(tempdir, "handmade_curved_opencrg_physics.fbx");
[fbxFile, mesh] = crg_write_fbx(crgFile, fbxFile, PhysicsMesh=true);
```

Create a Simulink 3D Actor directly from the mesh:

```matlab
[actor, mesh] = crg_create_sim3d_actor(crgFile, ...
    ActorName="OpenCRG_Road", ...
    PhysicsMesh=true);
```

The FBX mesh is intended for Unreal and Simulink 3D visualization or collision-style geometry. It is not a replacement for CRG road query semantics; use the C runtime or lookup exports for numerical road evaluation. `crg_write_fbx` uses Blender CLI when available and can be pointed to a specific executable with `BlenderExecutable`.

Useful mesh options:

- `NumLongitudinalSamples`: longitudinal mesh samples.
- `NumLateralSamples`: lateral mesh samples.
- `LaneVLimits`: export a lateral subset.
- `PhysicsMesh`: add underside and side faces for a closed physics-style volume.
- `Thickness`: underside offset in meters.
- `MaterialMode`: `"Elevation"`, `"Friction"` reserved, or `"None"`.

Run the demos:

```matlab
run(fullfile(repo, "matlab", "demo", "crg_demo_write_fbx.m"));
run(fullfile(repo, "matlab", "demo", "crg_demo_create_sim3d_actor.m"));
```

## Metrics And Validation

Collect modernization metrics:

```matlab
results = opencrg_modernization_metrics();
disp(results);
```

The metrics include Code Analyzer issue counts, representative read/evaluation timings, RRHD object creation timings, Simscape Grid Surface variable creation timing, lookup export timing, C runtime scalar-loop timing when a C MEX compiler is configured, and mesh/FBX export timing when Blender is available.

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
