function [lookup, data] = crg_export_lookup(source, matFile, options)
%CRG_EXPORT_LOOKUP Export OpenCRG data as lookup table variables.
%   LOOKUP = CRG_EXPORT_LOOKUP(SOURCE) returns a struct with u and v
%   breakpoints and table data from SOURCE.
%
%   SOURCE can be a CRG file name or a DATA struct as defined in CRG_INTRO.
%   File input can export long-section channels with non-elevation units,
%   such as friction coefficient data stored with unit "1".
%
%   CRG_EXPORT_LOOKUP(SOURCE, MATFILE) saves lookup, u, v, tableData, and
%   simulinkLookupTable variables to MATFILE.
%
%   Name-value options:
%       Channel                    "Auto", "Elevation", "Friction", or a label.
%       ChannelUnit                Long-section unit to select from the CRG file.
%       OutputClass                "double" or "single".
%       CreateSimulinkLookupTable  Create a Simulink.LookupTable object.
%       Write                      Save lookup variables to MATFILE.
%
%   Example:
%       lookup = crg_export_lookup("road.crg", Channel="Friction", ChannelUnit="1")
%
%   See also CRG_READ, IPL_READ.

arguments
    source
    matFile {mustBeTextScalar} = ""
    options.Channel (1, 1) string = "Auto"
    options.ChannelUnit (1, 1) string = ""
    options.OutputClass (1, 1) string = "double"
    options.CreateSimulinkLookupTable (1, 1) logical = true
    options.Write (1, 1) logical = true
end

options = crgLookupValidateOptions(options);
[data, sourceFile, tableUnit] = crgLookupReadSource(source, options);
matFile = crgLookupOutputFile(matFile, sourceFile, options.Write);
lookup = crgLookupStruct(data, tableUnit, options);

if options.CreateSimulinkLookupTable && exist("Simulink.LookupTable", "class") == 8
    lookup.SimulinkLookupTable = crgLookupSimulinkObject(lookup);
end

if options.Write
    crgLookupSave(matFile, lookup);
end
end

function options = crgLookupValidateOptions(options)
options.OutputClass = string(validatestring(options.OutputClass, ["double", "single"]));
options.Channel = strtrim(options.Channel);
options.ChannelUnit = strtrim(options.ChannelUnit);
end

function [data, sourceFile, tableUnit] = crgLookupReadSource(source, options)
if isstruct(source)
    data = source;
    if isfield(data, 'filenm')
        sourceFile = string(data.filenm);
    else
        sourceFile = "";
    end
    if ~isfield(data, 'ok')
        data = crg_check(data);
        if ~isfield(data, 'ok')
            error('CRG:lookupError', 'check of DATA was not completely successful')
        end
    end
    tableUnit = crgLookupUnitFromChannel(options.Channel, options.ChannelUnit, "m");
    data.u = crgLookupUValues(data.head, size(data.z, 1));
    data.v = crgLookupDataVValues(data, size(data.z, 2));
else
    sourceFile = string(source);
    [data, tableUnit] = crgLookupReadFile(sourceFile, options);
end

data.z = crgLookupCast(data.z, options.OutputClass);
data.u = crgLookupCast(data.u, options.OutputClass);
data.v = crgLookupCast(data.v, options.OutputClass);
end

function [data, tableUnit] = crgLookupReadFile(sourceFile, options)
ipl = ipl_read(sourceFile);
head = crgLookupReadHead(ipl.struct);
[tableData, vValues, tableUnit] = crgLookupLongSectionTable(ipl, head, options);
uValues = crgLookupUValues(head, size(tableData, 1));

data = struct();
data.filenm = sourceFile;
data.head = head;
data.u = uValues;
data.v = vValues;
data.z = tableData;
end

function head = crgLookupReadHead(structLines)
[roadBlock, ~] = sdf_cut(structLines, 'ROAD_CRG');
head = struct();
for lineIndex = 1:numel(roadBlock)
    line = regexprep(roadBlock{lineIndex}, '!+.*', '');
    [name, value, ok] = crgLookupParseNameNumber(line);
    if ~ok
        continue
    end
    switch lower(name)
        case 'reference_line_start_u'
            head.ubeg = value;
        case 'reference_line_end_u'
            head.uend = value;
        case 'reference_line_increment'
            head.uinc = value;
        case 'long_section_v_right'
            head.vmin = value;
        case 'long_section_v_left'
            head.vmax = value;
        case 'long_section_v_increment'
            head.vinc = value;
    end
end
end

function [name, value, ok] = crgLookupParseNameNumber(line)
parts = regexp(line, '^\s*([^=]+?)\s*=\s*([-+]?\d*\.?\d+(?:[eEdD][-+]?\d+)?)', ...
    'tokens', 'once');
ok = ~isempty(parts);
if ok
    name = strtrim(parts{1});
    value = str2double(strrep(parts{2}, 'D', 'E'));
else
    name = "";
    value = NaN;
end
end

function [tableData, vValues, tableUnit] = crgLookupLongSectionTable(ipl, head, options)
sections = crgLookupLongSections(ipl.kd_def);
if isempty(sections)
    error('CRG:lookupError', 'No long-section channels were found in the CRG file')
end

selectedUnit = crgLookupSelectUnit(sections.Unit, options.Channel, options.ChannelUnit);
selected = sections.Unit == selectedUnit;
if nnz(selected) < 2
    error('CRG:lookupError', 'At least two long-section channels are required for unit "%s"', selectedUnit)
end

sectionNumbers = sections.Position(selected);
channelIndices = sections.ChannelIndex(selected);
sectionModes = sections.Mode(selected);
if numel(unique(sectionModes)) ~= 1
    error('CRG:lookupError', 'Position-based and number-based long sections cannot be mixed')
end

if sectionModes(1) == "position"
    vValues = sectionNumbers;
else
    vValues = crgLookupNumberedVValues(head, numel(sectionNumbers));
end

[vValues, sortIndex] = sort(vValues);
vValues = reshape(vValues, 1, []);
channelIndices = channelIndices(sortIndex);
tableData = ipl.kd_dat(:, channelIndices);
tableUnit = selectedUnit;
end

function sections = crgLookupLongSections(channelDefinitions)
sections = table(strings(0, 1), zeros(0, 1), zeros(0, 1), strings(0, 1), ...
    VariableNames=["Unit", "Position", "ChannelIndex", "Mode"]);
for channelIndex = 1:numel(channelDefinitions)
    [channelName, channelUnit] = crgLookupDefinitionParts(channelDefinitions{channelIndex});
    if startsWith(channelName, "long section ")
        [position, mode, ok] = crgLookupLongSectionPosition(channelName);
        if ok
            sections(end+1, :) = {channelUnit, position, channelIndex, mode}; %#ok<AGROW>
        end
    end
end
end

function [channelName, channelUnit] = crgLookupDefinitionParts(definition)
parts = regexp(definition, '^(.*),([^,]*)$', 'tokens', 'once');
if isempty(parts)
    channelName = string(strtrim(definition));
    channelUnit = "";
else
    channelName = string(strtrim(parts{1}));
    channelUnit = string(strtrim(parts{2}));
end
end

function [position, mode, ok] = crgLookupLongSectionPosition(channelName)
position = NaN;
mode = "";
tokens = regexp(channelName, '^long section at v =\s*([-+]?\d*\.?\d+(?:[eEdD][-+]?\d+)?)', ...
    'tokens', 'once');
if ~isempty(tokens)
    position = str2double(strrep(tokens{1}, 'D', 'E'));
    mode = "position";
    ok = isfinite(position);
    return
end

tokens = regexp(channelName, '^long section\s+([-+]?\d*\.?\d+(?:[eEdD][-+]?\d+)?)', ...
    'tokens', 'once');
if ~isempty(tokens)
    position = str2double(strrep(tokens{1}, 'D', 'E'));
    mode = "number";
    ok = isfinite(position);
else
    ok = false;
end
end

function selectedUnit = crgLookupSelectUnit(units, channel, channelUnit)
uniqueUnits = unique(units, "stable");
if channelUnit ~= ""
    selectedUnit = channelUnit;
    if ~ismember(selectedUnit, uniqueUnits)
        error('CRG:lookupError', 'No long-section channels found for unit "%s"', selectedUnit)
    end
    return
end

preferredUnit = crgLookupPreferredUnit(channel);
if preferredUnit ~= "" && ismember(preferredUnit, uniqueUnits)
    selectedUnit = preferredUnit;
elseif isscalar(uniqueUnits)
    selectedUnit = uniqueUnits(1);
else
    error('CRG:lookupError', 'ChannelUnit is required because multiple long-section units exist')
end
end

function preferredUnit = crgLookupPreferredUnit(channel)
switch lower(channel)
    case {"z", "height", "elevation"}
        preferredUnit = "m";
    case {"friction", "mu"}
        preferredUnit = "1";
    otherwise
        preferredUnit = "";
end
end

function tableUnit = crgLookupUnitFromChannel(channel, channelUnit, fallbackUnit)
if channelUnit ~= ""
    tableUnit = channelUnit;
    return
end

tableUnit = crgLookupPreferredUnit(channel);
if tableUnit == ""
    tableUnit = fallbackUnit;
end
end

function vValues = crgLookupNumberedVValues(head, sectionCount)
if isfield(head, 'vinc')
    vIncrement = head.vinc;
else
    vIncrement = 0.010;
end

if isfield(head, 'vmin')
    vMinimum = head.vmin;
elseif isfield(head, 'vmax')
    vMinimum = head.vmax - vIncrement*(sectionCount - 1);
else
    vMinimum = -vIncrement*(sectionCount - 1)/2;
end

vValues = vMinimum + (0:sectionCount-1)*vIncrement;
end

function vValues = crgLookupDataVValues(data, columnCount)
if isfield(data.head, 'vinc') && data.head.vinc > 0
    vValues = linspace(data.head.vmin, data.head.vmax, columnCount);
elseif isfield(data, 'v') && isscalar(data.v)
    vValues = linspace(-double(data.v), double(data.v), columnCount);
elseif isfield(data, 'v') && numel(data.v) == 2
    vValues = linspace(double(data.v(1)), double(data.v(2)), columnCount);
elseif isfield(data, 'v') && numel(data.v) == columnCount
    vValues = double(reshape(data.v, 1, []));
elseif isfield(data.head, 'vmin') && isfield(data.head, 'vmax')
    vValues = linspace(data.head.vmin, data.head.vmax, columnCount);
else
    error('CRG:lookupError', 'Unable to determine OpenCRG lateral lookup breakpoints')
end
end

function uValues = crgLookupUValues(head, rowCount)
if isfield(head, 'ubeg')
    uBegin = head.ubeg;
else
    uBegin = 0;
end

if isfield(head, 'uinc')
    uValues = uBegin + (0:rowCount-1)*head.uinc;
elseif isfield(head, 'uend')
    uValues = linspace(uBegin, head.uend, rowCount);
else
    uValues = uBegin + (0:rowCount-1);
end
uValues = reshape(uValues, 1, []);
end

function lookup = crgLookupStruct(data, tableUnit, options)
lookup = struct( ...
    "Channel", options.Channel, ...
    "Breakpoints1", data.u, ...
    "Breakpoints2", data.v, ...
    "Table", data.z, ...
    "Breakpoints1Name", "u", ...
    "Breakpoints2Name", "v", ...
    "Breakpoints1Unit", "m", ...
    "Breakpoints2Unit", "m", ...
    "TableUnit", tableUnit, ...
    "SourceFile", string(data.filenm), ...
    "Description", "OpenCRG " + options.Channel + " lookup table");
end

function simulinkLookupTable = crgLookupSimulinkObject(lookup)
simulinkLookupTable = Simulink.LookupTable;
simulinkLookupTable.Table.Value = lookup.Table;
simulinkLookupTable.Table.Unit = lookup.TableUnit;
simulinkLookupTable.Table.FieldName = "tableData";
simulinkLookupTable.Table.Description = lookup.Description;
simulinkLookupTable.Breakpoints(1).Value = lookup.Breakpoints1;
simulinkLookupTable.Breakpoints(1).Unit = lookup.Breakpoints1Unit;
simulinkLookupTable.Breakpoints(1).FieldName = "u";
simulinkLookupTable.Breakpoints(1).Description = "OpenCRG longitudinal coordinate";
simulinkLookupTable.Breakpoints(2) = simulinkLookupTable.Breakpoints(1);
simulinkLookupTable.Breakpoints(2).Value = lookup.Breakpoints2;
simulinkLookupTable.Breakpoints(2).Unit = lookup.Breakpoints2Unit;
simulinkLookupTable.Breakpoints(2).FieldName = "v";
simulinkLookupTable.Breakpoints(2).Description = "OpenCRG lateral coordinate";
end

function value = crgLookupCast(value, outputClass)
switch outputClass
    case "double"
        value = double(value);
    case "single"
        value = single(value);
    otherwise
        error('CRG:lookupError', 'Unsupported output class: %s', outputClass)
end
end

function matFile = crgLookupOutputFile(matFile, sourceFile, writeOutput)
matFile = string(matFile);
if matFile == "" && writeOutput
    if sourceFile == ""
        error('CRG:lookupError', 'MATFILE is required when SOURCE is a data struct and Write is true')
    end
    [folder, name] = fileparts(sourceFile);
    matFile = fullfile(folder, name + "_Lookup.mat");
end

if matFile ~= ""
    [folder, name, extension] = fileparts(matFile);
    if extension == ""
        matFile = fullfile(folder, name + ".mat");
    end
end
end

function crgLookupSave(matFile, lookup)
u = lookup.Breakpoints1;
v = lookup.Breakpoints2;
tableData = lookup.Table;
if isfield(lookup, "SimulinkLookupTable")
    simulinkLookupTable = lookup.SimulinkLookupTable;
else
    simulinkLookupTable = [];
end
save(matFile, "lookup", "u", "v", "tableData", "simulinkLookupTable");
end
