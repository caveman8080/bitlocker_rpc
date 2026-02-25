#pragma once
#include <cuda_runtime.h>
#include <iostream>
#define CUDA_CHECK(call) \
    { cudaError_t err = call; if (err != cudaSuccess) { \
        std::cerr << "CUDA error: " << cudaGetErrorString(err) << std::endl; exit(1); } }
