function [actor, mesh] = crg_create_sim3d_actor(source, options)
%CRG_CREATE_SIM3D_ACTOR Create a Simulink 3D Actor from OpenCRG data.

arguments
    source
    options.ActorName (1, 1) string = "OpenCRG_Road"
    options.NumLongitudinalSamples (1, 1) double = NaN
    options.NumLateralSamples (1, 1) double = NaN
    options.LaneVLimits (1, 2) double = [NaN NaN]
    options.PhysicsMesh (1, 1) logical = true
    options.Thickness (1, 1) double = 0.05
    options.AddSkirts (1, 1) logical = true
    options.MaterialMode (1, 1) string = "Elevation"
    options.Mobility (1, 1) string = "Static"
end

if exist("sim3d.Actor", "class") ~= 8
    error("CRG:sim3dError", "sim3d.Actor is unavailable. Install Simulink 3D Animation.")
end

[mesh, ~] = crg_export_mesh(source, ...
    NumLongitudinalSamples=options.NumLongitudinalSamples, ...
    NumLateralSamples=options.NumLateralSamples, ...
    LaneVLimits=options.LaneVLimits, ...
    PhysicsMesh=options.PhysicsMesh, ...
    Thickness=options.Thickness, ...
    AddSkirts=options.AddSkirts, ...
    MaterialMode=options.MaterialMode);

actor = sim3d.Actor(ActorName=options.ActorName, Mobility=options.Mobility);
if isempty(mesh.VertexColor)
    createMesh(actor, double(mesh.Vertices), double(mesh.Normals), double(mesh.Faces));
else
    createMesh(actor, double(mesh.Vertices), double(mesh.Normals), double(mesh.Faces), ...
        double(mesh.UV), double(mesh.VertexColor));
end
actor.UserData = mesh.Metadata;
end
