#define S_FUNCTION_NAME crg_sfun_xy2z
#define S_FUNCTION_LEVEL 2

#include "simstruc.h"
#include "crg_runtime.h"
#include "crgBaseLib.h"

enum {
    PARAM_FILE_NAME = 0,
    PARAM_HISTORY_SIZE,
    PARAM_COUNT
};

enum {
    INPUT_X = 0,
    INPUT_Y,
    INPUT_RESET,
    INPUT_COUNT
};

enum {
    OUTPUT_U = 0,
    OUTPUT_V,
    OUTPUT_Z,
    OUTPUT_PHI,
    OUTPUT_CURVATURE,
    OUTPUT_STATUS,
    OUTPUT_COUNT
};

#define CONTEXT_WORK_INDEX 0

static void mdlInitializeSizes(SimStruct* S)
{
    int portIndex;

    ssSetNumSFcnParams(S, PARAM_COUNT);
    if (ssGetNumSFcnParams(S) != ssGetSFcnParamsCount(S)) {
        return;
    }

    for (portIndex = 0; portIndex < PARAM_COUNT; ++portIndex) {
        ssSetSFcnParamTunable(S, portIndex, SS_PRM_NOT_TUNABLE);
    }

    if (!ssSetNumInputPorts(S, INPUT_COUNT)) {
        return;
    }
    for (portIndex = 0; portIndex < INPUT_COUNT; ++portIndex) {
        ssSetInputPortWidth(S, portIndex, 1);
        ssSetInputPortDataType(S, portIndex, SS_DOUBLE);
        ssSetInputPortDirectFeedThrough(S, portIndex, 1);
        ssSetInputPortRequiredContiguous(S, portIndex, 1);
    }

    if (!ssSetNumOutputPorts(S, OUTPUT_COUNT)) {
        return;
    }
    for (portIndex = 0; portIndex < OUTPUT_COUNT; ++portIndex) {
        ssSetOutputPortWidth(S, portIndex, 1);
        ssSetOutputPortDataType(S, portIndex, SS_DOUBLE);
    }

    ssSetNumPWork(S, 1);
    ssSetNumSampleTimes(S, 1);
    ssSetOptions(S, SS_OPTION_EXCEPTION_FREE_CODE | SS_OPTION_WORKS_WITH_CODE_REUSE);
}

static void mdlInitializeSampleTimes(SimStruct* S)
{
    ssSetSampleTime(S, 0, INHERITED_SAMPLE_TIME);
    ssSetOffsetTime(S, 0, 0.0);
}

#define MDL_START
static void mdlStart(SimStruct* S)
{
#ifdef MATLAB_MEX_FILE
    char* fileName;
    int historySize;
    int status;
    CrgRuntimeContext* context;

    fileName = mxArrayToString(ssGetSFcnParam(S, PARAM_FILE_NAME));
    if (!fileName) {
        ssSetErrorStatus(S, "OpenCRG S-Function requires a CRG file name parameter.");
        return;
    }

    historySize = (int)mxGetScalar(ssGetSFcnParam(S, PARAM_HISTORY_SIZE));
    context = (CrgRuntimeContext*)mxCalloc(1, sizeof(CrgRuntimeContext));
    crgRuntimeContextSetDefaults(context);
    status = crgRuntimeInitializeFromFile(context, fileName, historySize, dCrgMsgLevelNone);
    mxFree(fileName);

    if (status != CRG_RUNTIME_STATUS_OK) {
        mxFree(context);
        ssSetErrorStatus(S, "Unable to initialize OpenCRG C runtime.");
        return;
    }

    ssSetPWorkValue(S, CONTEXT_WORK_INDEX, context);
#else
    ssSetErrorStatus(S, "OpenCRG S-Function requires inlining support for generated code.");
#endif
}

static void mdlOutputs(SimStruct* S, int_T tid)
{
    const real_T* xSignal = (const real_T*)ssGetInputPortSignal(S, INPUT_X);
    const real_T* ySignal = (const real_T*)ssGetInputPortSignal(S, INPUT_Y);
    const real_T* resetSignal = (const real_T*)ssGetInputPortSignal(S, INPUT_RESET);
    real_T* uSignal = ssGetOutputPortRealSignal(S, OUTPUT_U);
    real_T* vSignal = ssGetOutputPortRealSignal(S, OUTPUT_V);
    real_T* zSignal = ssGetOutputPortRealSignal(S, OUTPUT_Z);
    real_T* phiSignal = ssGetOutputPortRealSignal(S, OUTPUT_PHI);
    real_T* curvatureSignal = ssGetOutputPortRealSignal(S, OUTPUT_CURVATURE);
    real_T* statusSignal = ssGetOutputPortRealSignal(S, OUTPUT_STATUS);
    CrgRuntimeContext* context = (CrgRuntimeContext*)ssGetPWorkValue(S, CONTEXT_WORK_INDEX);
    int status;

    (void)tid;

    status = crgRuntimeStepXY(context, xSignal[0], ySignal[0], resetSignal[0] != 0.0,
        &uSignal[0], &vSignal[0], &zSignal[0], &phiSignal[0], &curvatureSignal[0]);
    statusSignal[0] = (real_T)status;
}

static void mdlTerminate(SimStruct* S)
{
    CrgRuntimeContext* context = (CrgRuntimeContext*)ssGetPWorkValue(S, CONTEXT_WORK_INDEX);

    if (context) {
        crgRuntimeTerminate(context);
#ifdef MATLAB_MEX_FILE
        mxFree(context);
#endif
        ssSetPWorkValue(S, CONTEXT_WORK_INDEX, NULL);
    }
}

#ifdef MATLAB_MEX_FILE
#include "simulink.c"
#else
#include "cg_sfun.h"
#endif
