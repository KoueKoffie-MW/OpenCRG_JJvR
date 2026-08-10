#ifndef CRG_RUNTIME_H
#define CRG_RUNTIME_H

#ifdef __cplusplus
extern "C" {
#endif

#define CRG_RUNTIME_STATUS_OK              0
#define CRG_RUNTIME_STATUS_NOT_INITIALIZED 1
#define CRG_RUNTIME_STATUS_RESET_FAILED    2
#define CRG_RUNTIME_STATUS_XY2UV_FAILED    4
#define CRG_RUNTIME_STATUS_UV2Z_FAILED     8
#define CRG_RUNTIME_STATUS_UV2PK_FAILED    16

typedef struct CrgRuntimeContextTag {
    int dataSetId;
    int contactPointId;
    int historySize;
    int initialized;
} CrgRuntimeContext;

void crgRuntimeContextSetDefaults(CrgRuntimeContext* context);

int crgRuntimeInitializeFromFile(CrgRuntimeContext* context,
                                 const char* fileName,
                                 int historySize,
                                 int messageLevel);

int crgRuntimeReset(CrgRuntimeContext* context);

int crgRuntimeStepXY(CrgRuntimeContext* context,
                     double x,
                     double y,
                     int resetRequested,
                     double* u,
                     double* v,
                     double* z,
                     double* phi,
                     double* curvature);

void crgRuntimeTerminate(CrgRuntimeContext* context);

int crgRuntimeSingletonInitializeFromFile(const char* fileName,
                                          int historySize,
                                          int messageLevel);

int crgRuntimeSingletonStepXY(double x,
                              double y,
                              int resetRequested,
                              double* u,
                              double* v,
                              double* z,
                              double* phi,
                              double* curvature);

void crgRuntimeSingletonTerminate(void);

#ifdef __cplusplus
}
#endif

#endif
