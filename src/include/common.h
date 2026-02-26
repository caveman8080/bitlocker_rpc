#pragma once

// Common project-wide definitions
// Add any shared macros, typedefs, or constants here

#ifndef BITLOCKER_RPC_COMMON_H
#define BITLOCKER_RPC_COMMON_H

// Example macro for CUDA error checking
#define CUDA_CHECK(call) \
    { cudaError_t err = call; if (err != cudaSuccess) { \
        std::cerr << "CUDA error: " << cudaGetErrorString(err) << std::endl; exit(1); } }

#endif // BITLOCKER_RPC_COMMON_H