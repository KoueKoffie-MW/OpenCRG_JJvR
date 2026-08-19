#include "mex.h"
#include "crg_runtime.h"
#include "crgBaseLib.h"
#include <stdint.h>
#include <string.h>

static CrgRuntimeContext runtimeContext;
static int runtimeDefaultsSet = 0;
static int atExitRegistered = 0;

static void crgMexEnsureDefaults(void)
{
    if (!runtimeDefaultsSet) {
        crgRuntimeContextSetDefaults(&runtimeContext);
        runtimeDefaultsSet = 1;
    }
}

static void crgMexClose(void)
{
    if (runtimeDefaultsSet) {
        crgRuntimeTerminate(&runtimeContext);
    }
}

static char* crgMexArrayToString(const mxArray* value, const char* errorId, const char* errorMessage)
{
    char* text = NULL;
    mxArray* charValue = NULL;

    if (mxIsChar(value)) {
        text = mxArrayToString(value);
    } else if (mxIsClass(value, "string")) {
        mxArray* rhs[1];
        rhs[0] = (mxArray*)value;
        if (mexCallMATLAB(1, &charValue, 1, rhs, "char") == 0) {
            text = mxArrayToString(charValue);
        }
        if (charValue) {
            mxDestroyArray(charValue);
        }
    }

    if (!text) {
        mexErrMsgIdAndTxt(errorId, "%s", errorMessage);
    }

    return text;
}

static char* crgMexCommand(const mxArray* value)
{
    return crgMexArrayToString(value, "OpenCRG:runtime:invalidCommand",
        "Command must be a character vector or string scalar.");
}

static void crgMexOpen(int nlhs, mxArray* plhs[], int nrhs, const mxArray* prhs[])
{
    char* fileName;
    int historySize = 50;
    int status;

    if (nrhs < 2) {
        mexErrMsgIdAndTxt("OpenCRG:runtime:open", "Open command requires a CRG file name.");
    }
    if (nlhs > 1) {
        mexErrMsgIdAndTxt("OpenCRG:runtime:open", "Open command returns one handle.");
    }

    crgMexEnsureDefaults();
    fileName = crgMexArrayToString(prhs[1], "OpenCRG:runtime:open", "Unable to read CRG file name.");
    if (nrhs >= 3) {
        historySize = (int)mxGetScalar(prhs[2]);
    }

    status = crgRuntimeInitializeFromFile(&runtimeContext, fileName, historySize, dCrgMsgLevelNone);
    mxFree(fileName);

    if (status != CRG_RUNTIME_STATUS_OK) {
        mexErrMsgIdAndTxt("OpenCRG:runtime:open", "Unable to initialize OpenCRG runtime.");
    }

    if (!atExitRegistered) {
        mexAtExit(crgMexClose);
        atExitRegistered = 1;
    }

    plhs[0] = mxCreateNumericMatrix(1, 1, mxUINT64_CLASS, mxREAL);
    *((uint64_t*)mxGetData(plhs[0])) = UINT64_C(1);
}

static void crgMexStep(int nlhs, mxArray* plhs[], int nrhs, const mxArray* prhs[])
{
    double x;
    double y;
    int resetRequested = 0;
    double u;
    double v;
    double z;
    double phi;
    double curvature;
    int status;

    if (nrhs < 4) {
        mexErrMsgIdAndTxt("OpenCRG:runtime:step", "Step command requires handle, x, and y.");
    }
    if (nlhs > 6) {
        mexErrMsgIdAndTxt("OpenCRG:runtime:step", "Step command returns up to six outputs.");
    }

    crgMexEnsureDefaults();
    x = mxGetScalar(prhs[2]);
    y = mxGetScalar(prhs[3]);
    if (nrhs >= 5) {
        resetRequested = mxGetScalar(prhs[4]) != 0.0;
    }

    status = crgRuntimeStepXY(&runtimeContext, x, y, resetRequested,
        &u, &v, &z, &phi, &curvature);

    if (nlhs > 0) {
        plhs[0] = mxCreateDoubleScalar(u);
    }
    if (nlhs > 1) {
        plhs[1] = mxCreateDoubleScalar(v);
    }
    if (nlhs > 2) {
        plhs[2] = mxCreateDoubleScalar(z);
    }
    if (nlhs > 3) {
        plhs[3] = mxCreateDoubleScalar(phi);
    }
    if (nlhs > 4) {
        plhs[4] = mxCreateDoubleScalar(curvature);
    }
    if (nlhs > 5) {
        plhs[5] = mxCreateDoubleScalar((double)status);
    }
}

static void crgMexPlane(int nlhs, mxArray* plhs[], int nrhs, const mxArray* prhs[])
{
    double x;
    double y;
    int resetRequested = 0;
    double px;
    double py;
    double pz;
    double iuCurrent;
    double qx;
    double qy;
    double qz;
    int status;

    if (nrhs < 4) {
        mexErrMsgIdAndTxt("OpenCRG:runtime:plane", "Plane command requires handle, x, and y.");
    }
    if (nlhs > 8) {
        mexErrMsgIdAndTxt("OpenCRG:runtime:plane", "Plane command returns up to eight outputs.");
    }

    crgMexEnsureDefaults();
    x = mxGetScalar(prhs[2]);
    y = mxGetScalar(prhs[3]);
    if (nrhs >= 5) {
        resetRequested = mxGetScalar(prhs[4]) != 0.0;
    }

    status = crgRuntimeStepTirePlaneXY(&runtimeContext, x, y, resetRequested,
        &px, &py, &pz, &iuCurrent, &qx, &qy, &qz);

    if (nlhs > 0) {
        plhs[0] = mxCreateDoubleScalar(px);
    }
    if (nlhs > 1) {
        plhs[1] = mxCreateDoubleScalar(py);
    }
    if (nlhs > 2) {
        plhs[2] = mxCreateDoubleScalar(pz);
    }
    if (nlhs > 3) {
        plhs[3] = mxCreateDoubleScalar(iuCurrent);
    }
    if (nlhs > 4) {
        plhs[4] = mxCreateDoubleScalar(qx);
    }
    if (nlhs > 5) {
        plhs[5] = mxCreateDoubleScalar(qy);
    }
    if (nlhs > 6) {
        plhs[6] = mxCreateDoubleScalar(qz);
    }
    if (nlhs > 7) {
        plhs[7] = mxCreateDoubleScalar((double)status);
    }
}

void mexFunction(int nlhs, mxArray* plhs[], int nrhs, const mxArray* prhs[])
{
    char* command;

    if (nrhs < 1) {
        mexErrMsgIdAndTxt("OpenCRG:runtime:usage", "Usage: crg_runtime_mex(command, ...).");
    }

    command = crgMexCommand(prhs[0]);
    if (strcmp(command, "open") == 0) {
        mxFree(command);
        crgMexOpen(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "step") == 0) {
        mxFree(command);
        crgMexStep(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "plane") == 0) {
        mxFree(command);
        crgMexPlane(nlhs, plhs, nrhs, prhs);
    } else if (strcmp(command, "close") == 0) {
        mxFree(command);
        crgMexClose();
    } else if (strcmp(command, "closeAll") == 0) {
        mxFree(command);
        crgMexClose();
    } else {
        mxFree(command);
        mexErrMsgIdAndTxt("OpenCRG:runtime:usage", "Unknown OpenCRG runtime command.");
    }
}
