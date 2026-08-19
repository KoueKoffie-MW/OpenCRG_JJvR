#include "crg_runtime.h"
#include "crgBaseLibPrivate.h"
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

static double crgRuntimeInterpolateChannelU(const CrgChannelStruct* channel,
                                            const CrgChannelStruct* channelU,
                                            double u)
{
    double fracU;
    size_t indexU;

    if (!channel || !channelU) {
        return 0.0;
    }

    if (!channel->info.valid || !channel->data || channel->info.size < 2 ||
        !channelU->info.valid || channelU->info.inc == 0.0) {
        return channel->info.first;
    }

    fracU = (u - channelU->info.first) / channelU->info.inc;
    if (fracU < 0.0) {
        indexU = 0;
        fracU = 0.0;
    } else {
        indexU = (size_t)fracU;
        if (indexU >= channel->info.size - 1) {
            indexU = channel->info.size - 2;
            fracU = 1.0;
        } else {
            fracU -= indexU;
        }
    }

    return channel->data[indexU] + fracU * (channel->data[indexU + 1] - channel->data[indexU]);
}

static int crgRuntimeEvaluateSlopeBank(const CrgRuntimeContext* context,
                                       double u,
                                       double* slope,
                                       double* bank)
{
    CrgDataStruct* crgData;

    if (slope) {
        *slope = 0.0;
    }
    if (bank) {
        *bank = 0.0;
    }

    if (!context || context->dataSetId <= 0) {
        return 0;
    }

    crgData = crgDataSetAccess(context->dataSetId);
    if (!crgData) {
        return 0;
    }

    if (slope) {
        *slope = crgRuntimeInterpolateChannelU(&crgData->channelSlope, &crgData->channelU, u);
    }
    if (bank) {
        *bank = crgRuntimeInterpolateChannelU(&crgData->channelBank, &crgData->channelU, u);
    }

    return 1;
}

static double crgRuntimeEvaluateIndexU(const CrgRuntimeContext* context, double u)
{
    CrgDataStruct* crgData;
    double indexValue;

    if (!context || context->dataSetId <= 0) {
        return crgRuntimeNaN();
    }

    crgData = crgDataSetAccess(context->dataSetId);
    if (!crgData || crgData->channelU.info.size == 0 || crgData->channelU.info.inc == 0.0) {
        return crgRuntimeNaN();
    }

    indexValue = floor((u - crgData->channelU.info.first) / crgData->channelU.info.inc) + 1.0;
    if (indexValue < 1.0) {
        indexValue = 1.0;
    }
    if (indexValue > (double)crgData->channelU.info.size) {
        indexValue = (double)crgData->channelU.info.size;
    }

    return indexValue;
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

    if (!isfinite(x) || !isfinite(y)) {
        return CRG_RUNTIME_STATUS_INVALID_INPUT;
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

    if (!isfinite(*u) || !isfinite(*v)) {
        return CRG_RUNTIME_STATUS_INVALID_INPUT;
    }

    if (!crgEvaluv2z(context->contactPointId, *u, *v, z)) {
        status |= CRG_RUNTIME_STATUS_UV2Z_FAILED;
    }

    if (!isfinite(*z)) {
        status |= CRG_RUNTIME_STATUS_UV2Z_FAILED;
    }

    if (!crgEvaluv2pk(context->contactPointId, *u, *v, phi, curvature)) {
        status |= CRG_RUNTIME_STATUS_UV2PK_FAILED;
    }

    return status;
}

int crgRuntimeStepTirePlaneXY(CrgRuntimeContext* context,
                              double x,
                              double y,
                              int resetRequested,
                              double* px,
                              double* py,
                              double* pz,
                              double* iuCurrent,
                              double* qx,
                              double* qy,
                              double* qz)
{
    double u = 0.0;
    double v = 0.0;
    double z = 0.0;
    double phi = 0.0;
    double curvature = 0.0;
    double slope = 0.0;
    double bank = 0.0;
    int status;

    if (px) {
        *px = x;
    }
    if (py) {
        *py = y;
    }
    if (pz) {
        *pz = crgRuntimeNaN();
    }
    if (iuCurrent) {
        *iuCurrent = crgRuntimeNaN();
    }
    if (qx) {
        *qx = 0.0;
    }
    if (qy) {
        *qy = 0.0;
    }
    if (qz) {
        *qz = 0.0;
    }

    status = crgRuntimeStepXY(context, x, y, resetRequested, &u, &v, &z, &phi, &curvature);
    if (status != CRG_RUNTIME_STATUS_OK) {
        return status;
    }

    if (!crgRuntimeEvaluateSlopeBank(context, u, &slope, &bank)) {
        status |= CRG_RUNTIME_STATUS_ORIENT_FAILED;
    }

    if (pz) {
        *pz = z;
    }
    if (iuCurrent) {
        *iuCurrent = crgRuntimeEvaluateIndexU(context, u);
    }
    if (qx) {
        *qx = atan(bank);
    }
    if (qy) {
        *qy = -atan(slope);
    }
    if (qz) {
        *qz = phi;
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

int crgRuntimeSingletonStepTirePlaneXY(double x,
                                       double y,
                                       int resetRequested,
                                       double* px,
                                       double* py,
                                       double* pz,
                                       double* iuCurrent,
                                       double* qx,
                                       double* qy,
                                       double* qz)
{
    if (!crgRuntimeSingletonDefaultsSet) {
        crgRuntimeContextSetDefaults(&crgRuntimeSingleton);
        crgRuntimeSingletonDefaultsSet = 1;
    }

    return crgRuntimeStepTirePlaneXY(&crgRuntimeSingleton, x, y, resetRequested,
        px, py, pz, iuCurrent, qx, qy, qz);
}

void crgRuntimeSingletonTerminate(void)
{
    if (crgRuntimeSingletonDefaultsSet) {
        crgRuntimeTerminate(&crgRuntimeSingleton);
    }
}
