//
//  stretch.cpp
//  SpotCore
//

#include "CStretch.h"
#include "signalsmith-stretch/signalsmith-stretch.h"

struct CStretch {
    signalsmith::stretch::SignalsmithStretch<float> stretch;
};

extern "C" {

CStretch *cstretch_create(int channels, float sampleRate) {
    auto *result = new CStretch();
    result->stretch.presetDefault(channels, sampleRate);
    return result;
}

void cstretch_destroy(CStretch *stretch) {
    delete stretch;
}

void cstretch_reset(CStretch *stretch) {
    stretch->stretch.reset();
}

int cstretch_input_latency(const CStretch *stretch) {
    return stretch->stretch.inputLatency();
}

int cstretch_output_latency(const CStretch *stretch) {
    return stretch->stretch.outputLatency();
}

void cstretch_set_transpose_semitones(CStretch *stretch, float semitones, float tonalityLimit) {
    stretch->stretch.setTransposeSemitones(semitones, tonalityLimit);
}

void cstretch_seek(CStretch *stretch, const float *const *inputs, int inputSamples, double playbackRate) {
    stretch->stretch.seek(inputs, inputSamples, playbackRate);
}

void cstretch_process(CStretch *stretch, const float *const *inputs, int inputSamples,
                      float *const *outputs, int outputSamples) {
    stretch->stretch.process(inputs, inputSamples, outputs, outputSamples);
}

void cstretch_flush(CStretch *stretch, float *const *outputs, int outputSamples, float playbackRate) {
    stretch->stretch.flush(outputs, outputSamples, playbackRate);
}

}
