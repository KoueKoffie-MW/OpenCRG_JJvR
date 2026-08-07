function [ier] = ipl_write(data, filename, type)
% IPL_WRITE Write IPLOS file.
%   IER = IPL_WRITE(DATA, FILENAME, TYPE) writes IPLOS data file
%
%   Inputs:
%   DATA        is a struct array with
%       DATA.struct     (optional) cell array of struct data lines
%       DATA.kd_ind     (optional) cell array of virtual channel definitions
%       DATA.kd_def     cell array of data channel definitions
%       DATA.kd_oth     (optional) cell array of other definitions
%       DATA.kd_dat     data array (single or double)
%   FILENAME    is the file to write
%   TYPE        is the data representation type to use
%               'KRBI'  binary float32
%               'KDBI'  binary float64
%               'LRFI'  ascii single precision
%               'LDFI'  ascii double precision
%
%   Outputs:
%   IER         error return code
%               = 0     successful
%               = -1    not successful
%
%   Example
%   ier = ipl_write(data, filename, type)
%      Writes an IPLOS file.
%
%   See also IPL_READ, IPL_DEMO.

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

[nr, nc] = size(data.kd_dat);
if isstring(filename)
    filename = char(filename);
end

% IPLOS file machineformat: ieee-be (IEEE floating point with big-endian byte ordering)
% IPLOS file encoding: ISO-8859-1 (latin1, explicitly supported since Matlab R2006a)
try
  fid = fopen(filename,'w','ieee-be','ISO-8859-1');
catch
  fid = fopen(filename,'w','ieee-be');
end
if fid < 0
    error('file %s could not be opened for write', filename)
end
fileCleanup = onCleanup(@() closeOpenFile(fid));

% write structured data

if isfield(data, 'struct')
    for i = 1:length(data.struct)
        hc = data.struct{i};
        if length(hc) > 72
            hc = hc(1:72);
            warning('IPL:recLengthExceeded', ...
            'data.struct{%d} too long:\n %s\nwill only be used as:\n %s', ...
            i, data.struct{i}, hc)
        end
        fprintf(fid, '%s\n', hc);
    end
end

% write date

fprintf(fid, '* written by %s at %s\n', mfilename, char(datetime("now", Format="yyyy-MM-dd HH:mm:ss")));

% write definition block for sequential data

fprintf(fid, '%s\n', '$KD_DEFINITION');

fprintf(fid, '#:%s\n', type);

if isfield(data, 'kd_ind')
    for i = 1:length(data.kd_ind)
        hc = data.kd_ind{i};
        if length(hc) > 72
            hc = hc(1:72);
            warning('IPL:recLengthExceeded', ...
            'data.kd_ind{%d} too long:\n %s\nwill only be used as:\n %s', ...
            i, data.kd_ind{i}, hc)
        end
        fprintf(fid, 'U:%s\n', hc);
    end
end

if nc ~= length(data.kd_def)
    error('wrong number of data definitions')
end

for i = 1:length(data.kd_def)
        hc = data.kd_def{i};
        if length(hc) > 72
            hc = hc(1:72);
            warning('IPL:recLengthExceeded', ...
            'data.kd_def{%d} too long:\n %s\nwill only be used as:\n %s', ...
            i, data.kd_def{i}, hc)
        end
    fprintf(fid, 'D:%s\n', hc);
end

if isfield(data, 'kd_oth')
    for i = 1:length(data.kd_oth)
        hc = data.kd_oth{i};
        if length(hc) > 72
            hc = hc(1:72);
            warning('IPL:recLengthExceeded', ...
            'data.kd_oth{%d} too long:\n %s\nwill only be used as:\n %s', ...
            i, data.kd_oth{i}, hc)
        end
        fprintf(fid, '%s\n', hc);
    end
end

fprintf(fid, '%s\n', '$');

% write separator

hc(1:72) = '$';
fprintf(fid, '%s\n', hc);

% write sequential data

switch type
    case 'KRBI'
        writeBinaryRows(fid, data.kd_dat, 'float32', 20);
    case 'KDBI'
        writeBinaryRows(fid, data.kd_dat, 'float64', 10);
    case 'LRFI'
        for ir = 1:nr
            for ic = 1:nc
                if isnan(data.kd_dat(ir, ic))
                    fprintf(fid, '**********');
                else
                    fprintf(fid, ' %s', str_num2strn(double(data.kd_dat(ir, ic)), 9));
                end
                if (mod(ic, 8) == 0)
                    fprintf(fid, '\n');
                end
            end
            if (mod(nc, 8) ~= 0)
                fprintf(fid, '\n');
            end
        end
    case 'LDFI'
        for ir = 1:nr
            for ic = 1:nc
                if isnan(data.kd_dat(ir, ic))
                    fprintf(fid, '********************');
                else
                    fprintf(fid, ' %s', str_num2strn(double(data.kd_dat(ir, ic)), 19));
                end
                if (mod(ic, 4) == 0)
                    fprintf(fid, '\n');
                end
            end
            if mod(nc, 4) ~= 0
                fprintf(fid, '\n');
            end
        end
     otherwise
        error('type %s is not supported', type)
end

ier = fclose(fid);
end

function writeBinaryRows(fid, values, precision, paddingMultiple)
[nr, nc] = size(values);
maxChunkElements = 5e6;
chunkRows = max(1, floor(maxChunkElements/max(nc, 1)));

for rowStart = 1:chunkRows:nr
    rowEnd = min(rowStart+chunkRows-1, nr);
    fwrite(fid, values(rowStart:rowEnd, :).', precision);
end

paddingCount = mod(-nc*nr, paddingMultiple);
if paddingCount > 0
    fwrite(fid, NaN(1, paddingCount), precision);
end
end

function closeOpenFile(fid)
if fid > 0 && any(openedFiles() == fid)
    fclose(fid);
end
end
