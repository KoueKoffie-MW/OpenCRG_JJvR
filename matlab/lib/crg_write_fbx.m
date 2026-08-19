function [fbxFile, mesh] = crg_write_fbx(source, fbxFile, options)
%CRG_WRITE_FBX Export an OpenCRG road mesh as an FBX file.

arguments
    source
    fbxFile {mustBeTextScalar} = ""
    options.NumLongitudinalSamples (1, 1) double = NaN
    options.NumLateralSamples (1, 1) double = NaN
    options.LaneVLimits (1, 2) double = [NaN NaN]
    options.PhysicsMesh (1, 1) logical = true
    options.Thickness (1, 1) double = 0.05
    options.AddSkirts (1, 1) logical = true
    options.MaterialMode (1, 1) string = "Elevation"
    options.OutputClass (1, 1) string = "double"
    options.EvalChunkSize (1, 1) double = 100000
    options.BlenderExecutable (1, 1) string = ""
    options.WriteIntermediate (1, 1) logical = false
end

fbxFile = crgFbxOutputFile(source, fbxFile);
[mesh, ~] = crg_export_mesh(source, ...
    NumLongitudinalSamples=options.NumLongitudinalSamples, ...
    NumLateralSamples=options.NumLateralSamples, ...
    LaneVLimits=options.LaneVLimits, ...
    PhysicsMesh=options.PhysicsMesh, ...
    Thickness=options.Thickness, ...
    AddSkirts=options.AddSkirts, ...
    MaterialMode=options.MaterialMode, ...
    OutputClass=options.OutputClass, ...
    EvalChunkSize=options.EvalChunkSize);

blenderExecutable = crgFbxFindBlender(options.BlenderExecutable);
[workingFolder, objFile, scriptFile] = crgFbxWorkingFiles(fbxFile);
if ~isfolder(workingFolder)
    mkdir(workingFolder);
end

crgFbxWriteObj(mesh, objFile);
crgFbxWriteBlenderScript(objFile, fbxFile, scriptFile);
cleanupFiles = onCleanup(@() crgFbxCleanup(objFile, scriptFile, options.WriteIntermediate));
command = """" + blenderExecutable + """ --background --python """ + scriptFile + """";
[status, commandOutput] = system(command);
if status ~= 0 || ~isfile(fbxFile)
    error("CRG:fbxError", "Blender FBX export failed: %s", commandOutput)
end

mesh.Metadata.FBXFile = string(fbxFile);
mesh.Metadata.BlenderExecutable = blenderExecutable;
clear cleanupFiles
if ~options.WriteIntermediate
    crgFbxCleanup(objFile, scriptFile, false);
end
end

function fbxFile = crgFbxOutputFile(source, fbxFile)
fbxFile = string(fbxFile);
if fbxFile ~= ""
    return
end

if isstruct(source) && isfield(source, "filenm")
    sourceFile = string(source.filenm);
elseif ~isstruct(source)
    sourceFile = string(source);
else
    sourceFile = "";
end

if sourceFile == ""
    error("CRG:fbxError", "FBXFILE is required when SOURCE does not provide a file name.")
end

[folder, name] = fileparts(sourceFile);
fbxFile = fullfile(folder, name + ".fbx");
end

function blenderExecutable = crgFbxFindBlender(blenderExecutable)
if blenderExecutable ~= ""
    if isfile(blenderExecutable)
        return
    end
    error("CRG:fbxError", "BlenderExecutable does not exist: %s", blenderExecutable)
end

environmentPath = string(getenv("BLENDER_EXECUTABLE"));
if environmentPath ~= "" && isfile(environmentPath)
    blenderExecutable = environmentPath;
    return
end

candidateFiles = [
    "C:\Program Files\Blender Foundation\Blender 5.0\blender.exe"
    "C:\Program Files\Blender Foundation\Blender 4.5\blender.exe"
    "C:\Program Files\Blender Foundation\Blender 4.4\blender.exe"
    "C:\Program Files\Blender Foundation\Blender 4.3\blender.exe"];
for candidateIndex = 1:numel(candidateFiles)
    if isfile(candidateFiles(candidateIndex))
        blenderExecutable = candidateFiles(candidateIndex);
        return
    end
end

[status, output] = system("where blender");
if status == 0
    blenderLines = splitlines(strtrim(string(output)));
    blenderLines = blenderLines(blenderLines ~= "");
    if ~isempty(blenderLines) && isfile(blenderLines(1))
        blenderExecutable = blenderLines(1);
        return
    end
end

error("CRG:fbxError", "Blender was not found. Set BlenderExecutable or BLENDER_EXECUTABLE.")
end

function [workingFolder, objFile, scriptFile] = crgFbxWorkingFiles(fbxFile)
[folder, name] = fileparts(fbxFile);
if folder == ""
    folder = pwd();
end
workingFolder = folder;
objFile = fullfile(workingFolder, name + "_opencrg_mesh.obj");
scriptFile = fullfile(workingFolder, name + "_opencrg_fbx_export.py");
end

function crgFbxWriteObj(mesh, objFile)
fileId = fopen(objFile, "w");
if fileId < 0
    error("CRG:fbxError", "Unable to open OBJ file for writing: %s", objFile)
end
cleanupFile = onCleanup(@() fclose(fileId));

fprintf(fileId, "# OpenCRG road mesh\n");
fprintf(fileId, "o OpenCRG_Road_Physics\n");
fprintf(fileId, "v %.17g %.17g %.17g\n", mesh.Vertices.');
fprintf(fileId, "vt %.17g %.17g\n", mesh.UV.');
fprintf(fileId, "vn %.17g %.17g %.17g\n", mesh.Normals.');
for faceIndex = 1:size(mesh.Faces, 1)
    face = mesh.Faces(faceIndex, :);
    fprintf(fileId, "f %d/%d/%d %d/%d/%d %d/%d/%d\n", ...
        face(1), face(1), face(1), face(2), face(2), face(2), face(3), face(3), face(3));
end
clear cleanupFile
end

function crgFbxWriteBlenderScript(objFile, fbxFile, scriptFile)
objLiteral = jsonencode(char(objFile));
fbxLiteral = jsonencode(char(fbxFile));
scriptLines = [
    "import bpy"
    "obj_file = " + objLiteral
    "fbx_file = " + fbxLiteral
    "bpy.ops.object.select_all(action='SELECT')"
    "bpy.ops.object.delete()"
    "if hasattr(bpy.ops.wm, 'obj_import'):"
    "    bpy.ops.wm.obj_import(filepath=obj_file)"
    "else:"
    "    bpy.ops.import_scene.obj(filepath=obj_file)"
    "for obj in bpy.context.scene.objects:"
    "    obj.name = 'OpenCRG_Road_Physics'"
    "    if hasattr(obj.data, 'name'):"
    "        obj.data.name = 'OpenCRG_Road_Physics_Mesh'"
    "bpy.context.scene.unit_settings.system = 'METRIC'"
    "bpy.ops.export_scene.fbx(filepath=fbx_file, use_selection=False, apply_unit_scale=True, global_scale=1.0, object_types={'MESH'})"];
writelines(scriptLines, scriptFile);
end

function crgFbxCleanup(objFile, scriptFile, keepIntermediate)
if keepIntermediate
    return
end
if isfile(objFile)
    delete(objFile);
end
if isfile(scriptFile)
    delete(scriptFile);
end
end
