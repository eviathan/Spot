//
//  CStretch.h
//  SpotCore
//
//  A small C interface to Signalsmith Stretch, so Swift can use it without C++ interop.
//  Buffers are arrays of per-channel pointers.
//

#ifndef CSTRETCH_H
#define CSTRETCH_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct CStretch CStretch;

CStretch *cstretch_create(int channels, float sampleRate);
void cstretch_destroy(CStretch *stretch);
void cstretch_reset(CStretch *stretch);

int cstretch_input_latency(const CStretch *stretch);
int cstretch_output_latency(const CStretch *stretch);

void cstretch_set_transpose_semitones(CStretch *stretch, float semitones, float tonalityLimit);

/// Moves the input position to the given audio (at least input latency + a block of it) without producing output.
void cstretch_seek(CStretch *stretch, const float *const *inputs, int inputSamples, double playbackRate);

/// Consumes `inputSamples` and produces `outputSamples`; their ratio is the local stretch.
void cstretch_process(CStretch *stretch, const float *const *inputs, int inputSamples,
                      float *const *outputs, int outputSamples);

/// Produces the last pending output after the input has run out.
void cstretch_flush(CStretch *stretch, float *const *outputs, int outputSamples, float playbackRate);

#ifdef __cplusplus
}
#endif

#endif
