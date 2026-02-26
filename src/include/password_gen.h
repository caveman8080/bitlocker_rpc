#pragma once
#include <cuda_runtime.h>

__device__ void generate_password(unsigned long long index, unsigned char* password);