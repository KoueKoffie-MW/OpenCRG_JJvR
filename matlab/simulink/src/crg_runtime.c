#include "crg_runtime.h"
#include "crgBaseLib.h"
#include <math.h>
#include <stddef.h>

static CrgRuntimeContext crgRuntimeSingleton;
static int crgRuntimeSingletonDefaultsSet = 0;

static double crgRuntimeNaN(void)
{
    return nan("");
}

static void crgRuntimeSetInvalidOutputs(double* u,
                                        double* v,
                                        double* z,
                                        double* phi,
                                        double* curvature)
{
    if (u) {
        *u = crgRuntimeNaN();
    }
    if (v) {
        *v = crgRuntimeNaN();
    }
    if (z) {
        *z = crgRuntimeNaN();
    }
    if (phi) {
        *phi = crgRuntimeNaN();
    }
    if (curvature) {
        *curvature = crgRuntimeNaN();
    }
}

static int crgRuntimeCreateContactPoint(CrgRuntimeContext* context)
{
    if (!context || context->dataSetId <= 0) {
        return 0;
    }

    context->contactPointId = crgContactPointCreate(context->dataSetId);
    if (context->contactPointId < 0) {
        return 0;
    }

    if (context->historySize >= 0) {
        return crgContactPointSetHistory(context->contactPointId, context->historySize);
    }

    return 1;
}

void crgRuntimeContextSetDefaults(CrgRuntimeContext* context)
{
    if (!context) {
        return;
    }

    context->dataSetId = 0;
    context->contactPointId = -1;
    context->historySize = 50;
    context->initialized = 0;
}

int crgRuntimeInitializeFromFile(CrgRuntimeContext* context,
                                 const char* fileName,
                                 int historySize,
                                 int messageLevel)
{
    if (!context || !fileName) {
        return CRG_RUNTIME_STATUS_NOT_INITIALIZED;
    }

    crgRuntimeTerminate(context);
    crgRuntimeContextSetDefaults(context);
    context->historySize = historySize;

    crgMsgSetLevel(messageLevel);
    crgLoaderSuppressFileNotFoundFatalMsg(true);
    context->dataSetId = crgLoaderReadFile(fileName);
    if (context->dataSetId <= 0) {
        crgRuntimeTerminate(context);
        return CRG_RUNTIME_STATUS_NOT_INITIALIZED;
    }

    if (!crgCheck(context->dataSetId)) {
        crgRuntimeTerminate(context);
        return CRG_RUNTIME_STATUS_NOT_INITIALIZED;
    }

    crgDataSetModifiersApply(context->dataSetId);

    if (!crgRuntimeCreateContactPoint(context)) {
        crgRuntimeTerminate(context);
        return CRG_RUNTIME_STATUS_NOT_INITIALIZED;
    }

    context->initialized = 1;
    return CRG_RUNTIME_STATUS_OK;
}

int crgRuntimeReset(CrgRuntimeContext* context)
{
    if (!context || !context->initialized) {
        return CRG_RUNTIME_STATUS_NOT_INITIALIZED;
    }

    if (context->contactPointId >= 0) {
        crgContactPointDelete(context->contactPointId);
        context->contactPointId = -1;
    }

    if (!crgRuntimeCreateContactPoint(context)) {
        context->initialized = 0;
        return CRG_RUNTIME_STATUS_RESET_FAILED;
    }

    context->initialized = 1;
    return CRG_RUNTIME_STATUS_OK;
}

int crgRuntimeStepXY(CrgRuntimeContext* context,
                     double x,
                     double y,
                     int resetRequested,
                     double* u,
                     double* v,
                     double* z,
                     double* phi,
                     double* curvature)
{
    int status = CRG_RUNTIME_STATUS_OK;

    crgRuntimeSetInvalidOutputs(u, v, z, phi, curvature);

    if (!context || !context->initialized || context->contactPointId < 0) {
        return CRG_RUNTIME_STATUS_NOT_INITIALIZED;
    }

    if (resetRequested) {
        status = crgRuntimeReset(context);
        if (status != CRG_RUNTIME_STATUS_OK) {
            return status;
        }
    }

    if (!crgEvalxy2uv(context->contactPointId, x, y, u, v)) {
        return CRG_RUNTIME_STATUS_XY2UV_FAILED;
    }

    if (!crgEvaluv2z(context->contactPointId, *u, *v, z)) {
        status |= CRG_RUNTIME_STATUS_UV2Z_FAILED;
    }

    if (!crgEvaluv2pk(context->contactPointId, *u, *v, phi, curvature)) {
        status |= CRG_RUNTIME_STATUS_UV2PK_FAILED;
    }

    return status;
}

void crgRuntimeTerminate(CrgRuntimeContext* context)
{
    if (!context) {
        return;
    }

    if (context->contactPointId >= 0) {
        crgContactPointDelete(context->contactPointId);
    }

    if (context->dataSetId > 0) {
        crgDataSetRelease(context->dataSetId);
    }

    crgRuntimeContextSetDefaults(context);
}

int crgRuntimeSingletonInitializeFromFile(const char* fileName,
                                          int historySize,
                                          int messageLevel)
{
    if (!crgRuntimeSingletonDefaultsSet) {
        crgRuntimeContextSetDefaults(&crgRuntimeSingleton);
        crgRuntimeSingletonDefaultsSet = 1;
    }

    return crgRuntimeInitializeFromFile(&crgRuntimeSingleton, fileName, historySize, messageLevel);
}

int crgRuntimeSingletonStepXY(double x,
                              double y,
                              int resetRequested,
                              double* u,
                              double* v,
                              double* z,
                              double* phi,
                              double* curvature)
{
    if (!crgRuntimeSingletonDefaultsSet) {
        crgRuntimeContextSetDefaults(&crgRuntimeSingleton);
        crgRuntimeSingletonDefaultsSet = 1;
    }

    return crgRuntimeStepXY(&crgRuntimeSingleton, x, y, resetRequested, u, v, z, phi, curvature);
}

void crgRuntimeSingletonTerminate(void)
{
    if (crgRuntimeSingletonDefaultsSet) {
        crgRuntimeTerminate(&crgRuntimeSingleton);
    }
}
