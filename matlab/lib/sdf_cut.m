function [sdf_block, sdf_out] = sdf_cut(sdf_in, blockname)
% SDF_CUT Cut block from struct data file.
%   [SDF_BLOCK SDF_OUT] = SDF_CUT(SDF_IN, BLOCKNAME) cuts a block from a struct
%   data file.
%
%   Inputs:
%   SDF_IN      cell array of struct data file lines
%   BLOCKNAME   name of block to cut out
%
%   Outputs:
%   SDF_BLOCK   cell array of struct data lines of named block
%   SDF_OUT     cell array of remaining struct data lines
%
%   Example:
%   [sdf_block, sdf_out] = sdf_cut(sdf_in, blockname) extracts a SDF block.
%
%   See also SDF_ADD.

% *****************************************************************
% See the NOTICE file distributed with this work regarding copyright ownership.
%
% Licensed under the Apache License, Version 2.0 (the "License");
% you may not use this file except in compliance with the License.
% You may obtain a copy of the License at
%
%    https://www.apache.org/licenses/LICENSE-2.0
%
% Unless required by applicable law or agreed to in writing, software
% distributed under the License is distributed on an "AS IS" BASIS,
% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
% See the License for the specific language governing permissions and
% limitations under the License.
%
% More Information on ASAM OpenCRG can be found here:
% https://www.asam.net/standards/detail/opencrg/
%
% *****************************************************************

state = 0;

hc = strcat('$', blockname);
lineCount = numel(sdf_in);
sdf_block = cell(1, lineCount);
sdf_out = cell(1, lineCount);
blockCount = 0;
outCount = 0;

for i = 1:lineCount
    switch state
        case 0 % outside of $BLOCKNAME
            if strcmpi(firstSdfToken(sdf_in{i}), hc)
                state = 1; % begin of $BLOCKNAME detected
            else
                outCount = outCount + 1;
                sdf_out{outCount} = sdf_in{i};
            end
        case 1 % inside of $BLOCKNAME
            if strncmp(sdf_in{i}, '$', 1)
                if strncmp(sdf_in{i}, '$$', 2)
                    blockCount = blockCount + 1;
                    sdf_block{blockCount} = sdf_in{i}(2:end);
                else
                    state = 2; % end of $BLOCKNAME detected
                end
            else
                blockCount = blockCount + 1;
                sdf_block{blockCount} = sdf_in{i};
            end
        case 2 % after end of $BLOCKNAME
            outCount = outCount + 1;
            sdf_out{outCount} = sdf_in{i};
    end
end

sdf_block = sdf_block(1:blockCount);
sdf_out = sdf_out(1:outCount);

end

function token = firstSdfToken(line)
line = strtrim(line);
delimiter = find(line == ' ' | line == '!', 1);
if isempty(delimiter)
    token = line;
else
    token = line(1:delimiter-1);
end
end
