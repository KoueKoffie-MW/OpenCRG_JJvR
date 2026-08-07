function tests = tOpenCRGModernization()
%TOPENCRGMODERNIZATION Regression tests for MATLAB modernization work.

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
testFolder = string(fileparts(mfilename("fullpath")));
matlabFolder = fileparts(testFolder);
repoRoot = fileparts(matlabFolder);

testCase.TestData.Repository = repoRoot;
testCase.TestData.Matlab = matlabFolder;
testCase.TestData.CrgText = fullfile(repoRoot, "crg-txt");
testCase.TestData.CrgBinary = fullfile(repoRoot, "crg-bin");

testCase.applyFixture(matlab.unittest.fixtures.PathFixture(matlabFolder));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(matlabFolder, "lib")));
testCase.applyFixture(matlab.unittest.fixtures.PathFixture(testFolder));
end

function testSelectedFormattedChannel(testCase)
file = fullfile(testCase.TestData.CrgText, "handmade_curved.crg");
allChannels = ipl_read(file);
selected = ipl_read(file, struct("channel", "long section at v =  0.000,m"));
channelIndex = find(strcmp(selected.kd_def{1}, allChannels.kd_def), 1);

verifyEqual(testCase, size(selected.kd_dat, 2), 1);
verifyEqual(testCase, selected.kd_dat, allChannels.kd_dat(:, channelIndex));
end

function testLongRecordsAreTruncatedOnWrite(testCase)
fixture = testCase.applyFixture(matlab.unittest.fixtures.TemporaryFolderFixture());
file = fullfile(fixture.Folder, "long-record.crg");

data.struct = {repmat('A', 1, 90)};
data.kd_def = {"channel one,m"};
data.kd_dat = single((1:3).');

verifyWarning(testCase, @() ipl_write(data, file, "LRFI"), "IPL:recLengthExceeded");
lines = readlines(file, Encoding="ISO-8859-1");
verifyLessThanOrEqual(testCase, strlength(lines(1)), 72);
end

function testCrgReadRepresentativeSamples(testCase)
textFile = fullfile(testCase.TestData.CrgText, "handmade_curved.crg");
binaryFile = fullfile(testCase.TestData.CrgBinary, "belgian_block.crg");

textData = crg_read(textFile);
binaryData = crg_read(binaryFile);

verifyClass(testCase, textData.z, "single");
verifyClass(testCase, binaryData.z, "single");
verifyGreaterThanOrEqual(testCase, size(textData.z, 1), 2);
verifyGreaterThanOrEqual(testCase, size(binaryData.z, 2), 2);
end

function testEvaluationKernelsPreserveShapes(testCase)
data = crg_read(fullfile(testCase.TestData.CrgBinary, "belgian_block.crg"));
u = linspace(data.head.ubeg, data.head.uend, 25);
v = linspace(data.head.vmin, data.head.vmax, 25);
puv = [u(:) v(:)];

phi = crg_eval_u2phi(data, u);
crv = crg_eval_u2crv(data, u);
[iu, iv] = crg_eval_uv2iuiv(data, u, v);
z = crg_eval_uv2z(data, puv);
xy = crg_eval_uv2xy(data, puv);

verifySize(testCase, phi, [1 25]);
verifySize(testCase, crv, [1 25]);
verifySize(testCase, iu, [1 25]);
verifySize(testCase, iv, [1 25]);
verifySize(testCase, z, [25 1]);
verifySize(testCase, xy, [25 2]);
verifyTrue(testCase, all(isfinite(xy), "all"));
end

function testUv2zVectorizedMatchesScalarCalls(testCase)
files = [
    fullfile(testCase.TestData.CrgText, "handmade_curved.crg")
    fullfile(testCase.TestData.CrgBinary, "belgian_block.crg")
    ];

for file = files.'
    baseData = crg_read(file);
    u = linspace(baseData.head.ubeg - 2*baseData.head.uinc, baseData.head.uend + 2*baseData.head.uinc, 40).';
    v = linspace(baseData.head.vmin - 1, baseData.head.vmax + 1, 40).';
    puv = [u v];

    for bdmu = 0:4
        for bdmv = 0:4
            data = baseData;
            data.opts.bdmu = bdmu;
            data.opts.bdmv = bdmv;
            vectorized = crg_eval_uv2z(data, puv);
            scalar = zeros(size(vectorized));
            for k = 1:size(puv, 1)
                scalar(k) = crg_eval_uv2z(data, puv(k, :));
            end
            verifyEqual(testCase, isnan(vectorized), isnan(scalar));
            finiteMask = isfinite(vectorized) & isfinite(scalar);
            verifyEqual(testCase, vectorized(finiteMask), scalar(finiteMask), AbsTol=1e-10);
        end
    end
end
end

function testMetricsSuiteRuns(testCase)
results = opencrg_modernization_metrics();
verifyGreaterThan(testCase, height(results), 3);
verifyTrue(testCase, all(ismember(["Metric", "Value", "Unit", "Notes"], string(results.Properties.VariableNames))));
end
