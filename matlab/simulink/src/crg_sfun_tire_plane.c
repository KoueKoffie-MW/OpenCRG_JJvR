#define S_FUNCTION_NAME crg_sfun_tire_plane
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
    INPUT_PZ_PREVIOUS,
    INPUT_X_PREVIOUS,
    INPUT_Y_PREVIOUS,
    INPUT_IU_PREVIOUS,
    INPUT_COUNT
};

enum {
    OUTPUT_PX = 0,
    OUTPUT_PY,
    OUTPUT_PZ,
    OUTPUT_IU_CURRENT,
    OUTPUT_QX,
    OUTPUT_QY,
    OUTPUT_QZ,
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
#if defined(ssSetRuntimeThreadSafetyCompliance) && defined(RUNTIME_THREAD_SAFETY_COMPLIANCE_FALSE)
    ssSetRuntimeThreadSafetyCompliance(S, RUNTIME_THREAD_SAFETY_COMPLIANCE_FALSE);
#endif
    ssSetNumSampleTimes(S, 1);
    ssSetOptions(S, SS_OPTION_EXCEPTION_FREE_CODE);
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
        ssSetErrorStatus(S, "OpenCRG tire-plane S-Function requires a CRG file name parameter.");
        return;
    }

    historySize = (int)mxGetScalar(ssGetSFcnParam(S, PARAM_HISTORY_SIZE));
    context = (CrgRuntimeContext*)mxCalloc(1, sizeof(CrgRuntimeContext));
    crgRuntimeContextSetDefaults(context);
    status = crgRuntimeInitializeFromFile(context, fileName, historySize, dCrgMsgLevelNone);
    mxFree(fileName);

    if (status != CRG_RUNTIME_STATUS_OK) {
        mxFree(context);
        ssSetErrorStatus(S, "Unable to initialize OpenCRG tire-plane C runtime.");
        return;
    }

    ssSetPWorkValue(S, CONTEXT_WORK_INDEX, context);
#else
    ssSetErrorStatus(S, "OpenCRG tire-plane S-Function requires inlining support for generated code.");
#endif
}

static void mdlOutputs(SimStruct* S, int_T tid)
{
    const real_T* xSignal = (const real_T*)ssGetInputPortSignal(S, INPUT_X);
    const real_T* ySignal = (const real_T*)ssGetInputPortSignal(S, INPUT_Y);
    const real_T* pzPreviousSignal = (const real_T*)ssGetInputPortSignal(S, INPUT_PZ_PREVIOUS);
    const real_T* iuPreviousSignal = (const real_T*)ssGetInputPortSignal(S, INPUT_IU_PREVIOUS);
    real_T* pxSignal = ssGetOutputPortRealSignal(S, OUTPUT_PX);
    real_T* pySignal = ssGetOutputPortRealSignal(S, OUTPUT_PY);
    real_T* pzSignal = ssGetOutputPortRealSignal(S, OUTPUT_PZ);
    real_T* iuCurrentSignal = ssGetOutputPortRealSignal(S, OUTPUT_IU_CURRENT);
    real_T* qxSignal = ssGetOutputPortRealSignal(S, OUTPUT_QX);
    real_T* qySignal = ssGetOutputPortRealSignal(S, OUTPUT_QY);
    real_T* qzSignal = ssGetOutputPortRealSignal(S, OUTPUT_QZ);
    CrgRuntimeContext* context = (CrgRuntimeContext*)ssGetPWorkValue(S, CONTEXT_WORK_INDEX);
    int status;

    (void)tid;
    (void)ssGetInputPortSignal(S, INPUT_X_PREVIOUS);
    (void)ssGetInputPortSignal(S, INPUT_Y_PREVIOUS);

    status = crgRuntimeStepTirePlaneXY(context, xSignal[0], ySignal[0], 0,
        &pxSignal[0], &pySignal[0], &pzSignal[0], &iuCurrentSignal[0],
        &qxSignal[0], &qySignal[0], &qzSignal[0]);

    if (status != CRG_RUNTIME_STATUS_OK) {
        pxSignal[0] = xSignal[0];
        pySignal[0] = ySignal[0];
        pzSignal[0] = pzPreviousSignal[0];
        iuCurrentSignal[0] = iuPreviousSignal[0];
        qxSignal[0] = 0.0;
        qySignal[0] = 0.0;
        qzSignal[0] = 0.0;
    }
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
