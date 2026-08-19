function blockPath = crg_replace_tire_plane_block(blockPath, crgFile, options)
%CRG_REPLACE_TIRE_PLANE_BLOCK Replace a legacy tire-plane block.

arguments
    blockPath {mustBeTextScalar}
    crgFile {mustBeTextScalar}
    options.HistorySize (1, 1) double {mustBeInteger, mustBePositive} = 50
end

blockPath = string(blockPath);
blockHandle = getSimulinkBlockHandle(char(blockPath));

if blockHandle < 0
    error("OpenCRG:tirePlaneBlockNotFound", "Block '%s' does not exist.", blockPath);
end

portHandles = get_param(blockHandle, "PortHandles");
position = get_param(blockHandle, "Position");
parentPath = string(get_param(blockHandle, "Parent"));
inputLinks = localCaptureInputLinks(portHandles.Inport, 6);
outputLinks = localCaptureOutputLinks(portHandles.Outport, 7);

if numel(portHandles.Inport) > 6
    warning("OpenCRG:tirePlaneExtraInputs", ...
        "Only the first six numeric legacy inputs are reconnected. CRG data is now a block parameter.");
end

localDeleteCapturedLines(inputLinks, outputLinks);
delete_block(char(blockPath));
crg_add_tire_plane_block(blockPath, crgFile, HistorySize=options.HistorySize, Position=position);
newPortHandles = get_param(char(blockPath), "PortHandles");

localReconnectInputs(parentPath, inputLinks, newPortHandles.Inport);
localReconnectOutputs(parentPath, outputLinks, newPortHandles.Outport);
end

function links = localCaptureInputLinks(portHandles, maxPorts)
links = repmat(struct("SourcePort", -1, "Line", -1), 1, maxPorts);
portCount = min(numel(portHandles), maxPorts);

for portIndex = 1:portCount
    lineHandle = get_param(portHandles(portIndex), "Line");
    if lineHandle ~= -1
        links(portIndex).Line = lineHandle;
        links(portIndex).SourcePort = get_param(lineHandle, "SrcPortHandle");
    end
end
end

function links = localCaptureOutputLinks(portHandles, maxPorts)
links = repmat(struct("DestinationPorts", [], "Line", -1), 1, maxPorts);
portCount = min(numel(portHandles), maxPorts);

for portIndex = 1:portCount
    lineHandle = get_param(portHandles(portIndex), "Line");
    if lineHandle ~= -1
        links(portIndex).Line = lineHandle;
        links(portIndex).DestinationPorts = get_param(lineHandle, "DstPortHandle");
    end
end
end

function localDeleteCapturedLines(inputLinks, outputLinks)
lineHandles = [inputLinks.Line outputLinks.Line];
lineHandles = unique(lineHandles(lineHandles ~= -1));

for lineIndex = 1:numel(lineHandles)
    delete_line(lineHandles(lineIndex));
end
end

function localReconnectInputs(parentPath, links, portHandles)
for portIndex = 1:numel(links)
    if links(portIndex).SourcePort ~= -1
        add_line(char(parentPath), links(portIndex).SourcePort, portHandles(portIndex), ...
            "autorouting", "on");
    end
end
end

function localReconnectOutputs(parentPath, links, portHandles)
for portIndex = 1:numel(links)
    destinationPorts = links(portIndex).DestinationPorts;
    for destinationIndex = 1:numel(destinationPorts)
        add_line(char(parentPath), portHandles(portIndex), destinationPorts(destinationIndex), ...
            "autorouting", "on");
    end
end
end
