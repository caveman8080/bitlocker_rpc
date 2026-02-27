#include <cuda_runtime.h>
#include <iostream>
#include <string>
#include <vector>
#include <sstream>
#include <stdexcept>
#include <iomanip>
#include <cstdint>
#include <cstring>
#include <thread>
#include <chrono>
#include <cstdlib>
#include <getopt.h>
#include <fstream>
#include <cctype>
#ifdef _WIN32
#include <conio.h>
#endif

#include "include/hash_parser.h"
#include "include/password_gen.h"
#include "include/kernel.h"
#include "include/utils.h"
#include "crypto/sha256.h"
#include "crypto/hmac_sha256.h"
#include "crypto/pbkdf2.h"
#include "crypto/aes_ccm.h"
#include "crypto/aes256.h"
#include <climits>

#define CUDA_CHECK(call) \
    { cudaError_t err = call; if (err != cudaSuccess) { \
        std::cerr << "CUDA error: " << cudaGetErrorString(err) << std::endl; exit(1); } }

bool running = true;
unsigned long long total_candidates_tested = 0;

int main(int argc, char* argv[]) {
    std::string hash_str;
    std::string input_file;
    std::string output_file = "found.txt";
    int threads_per_block = 256;
    int blocks = 256;

    int opt;
    bool enable_profile = false;
    // Support --profile as a flag
    for (int i = 1; i < argc; ++i) {
        if (std::string(argv[i]) == "--profile") {
            enable_profile = true;
        }
    }
    while ((opt = getopt(argc, argv, "hf:t:b:o:")) != -1) {
        switch (opt) {
            case 'h':
                std::cout << "Usage: " << argv[0] << " [options] [hash]" << std::endl;
                std::cout << "Options:" << std::endl;
                std::cout << "  -h        Show this help message and exit." << std::endl;
                std::cout << "  -f <file> Input file containing the BitLocker hash." << std::endl;
                std::cout << "  -t <num>  Set the number of threads per block (default: 256)." << std::endl;
                std::cout << "  -b <num>  Set the number of blocks (default: 256)." << std::endl;
                std::cout << "  -o <file> Output the found recovery key to the specified file (default: found.txt in current directory)." << std::endl;
                std::cout << "  --profile Enable launch profiling output." << std::endl;
                return 0;
            case 'f':
                input_file = optarg;
                break;
            case 't':
                threads_per_block = std::atoi(optarg);
                break;
            case 'b':
                blocks = std::atoi(optarg);
                break;
            case 'o':
                output_file = optarg;
                break;
            default:
                std::cerr << "Unknown option: -" << char(optopt) << std::endl;
                return 1;
        }
    }

    if (!input_file.empty()) {
        std::ifstream ifs(input_file);
        if (!ifs) {
            std::cerr << "Error opening input file: " << input_file << std::endl;
            return 1;
        }
        std::stringstream ss;
        ss << ifs.rdbuf();
        hash_str = ss.str();
        if (!hash_str.empty() && hash_str.back() == '\n') {
            hash_str.pop_back();
        }
    } else if (optind < argc) {
        hash_str = argv[optind];
    } else {
        std::cerr << "No hash provided. Use -h for help." << std::endl;
        return 1;
    }

    try {
        HashParams params = parse_hash(hash_str);

        unsigned char *d_salt, *d_nonce, *d_encrypted, *d_result_password;
        int *d_found_flag;
        CUDA_CHECK(cudaMalloc(&d_salt, params.salt.size()));
        CUDA_CHECK(cudaMalloc(&d_nonce, params.iv.size()));
        CUDA_CHECK(cudaMalloc(&d_encrypted, params.encrypted_data.size()));
        CUDA_CHECK(cudaMalloc(&d_found_flag, sizeof(int)));
        CUDA_CHECK(cudaMalloc(&d_result_password, 56));

        CUDA_CHECK(cudaMemcpy(d_salt, params.salt.data(), params.salt.size(), cudaMemcpyHostToDevice));
        CUDA_CHECK(cudaMemcpy(d_nonce, params.iv.data(), params.iv.size(), cudaMemcpyHostToDevice));
        CUDA_CHECK(cudaMemcpy(d_encrypted, params.encrypted_data.data(), params.encrypted_data.size(), cudaMemcpyHostToDevice));
        CUDA_CHECK(cudaMemset(d_found_flag, 0, sizeof(int)));

        unsigned long long candidates_per_launch = static_cast<unsigned long long>(blocks) * threads_per_block;

        // Safety: `sha256_warp` uses an internal shared buffer sized for up to 8 warps (256 threads).
        // Prevent users from requesting a larger `threads_per_block` which would overflow shared buffers.
        if (threads_per_block > 256) {
            std::cerr << "Error: threads_per_block > 256 is not supported by warp-cooperative SHA256 implementation." << std::endl;
            return 1;
        }

        std::thread progress_thread(display_progress);
        std::thread gpu_thread(display_gpu_utilization);

        unsigned long long max_index = 1ULL;
        bool overflowed = false;
        for (int i = 0; i < 8; i++) {
            if (max_index > ULLONG_MAX / 90909ULL) { overflowed = true; max_index = ULLONG_MAX; break; }
            max_index *= 90909ULL;
        }
        if (overflowed) {
            std::cerr << "Warning: total candidate space (90909^8) exceeds 64-bit and cannot be represented.\n"
                      << "Iteration will be limited to 2^64-1; use range options to restrict search." << std::endl;
        }

        for (unsigned long long start = 0; start < max_index; start += candidates_per_launch) {
            // region profiling buffers: [0]=PBKDF2 cycles, [1]=AES-CCM cycles
            unsigned long long *d_region_cycles;
            unsigned long long *d_region_counts;
            CUDA_CHECK(cudaMalloc(&d_region_cycles, sizeof(unsigned long long) * 2));
            CUDA_CHECK(cudaMalloc(&d_region_counts, sizeof(unsigned long long) * 2));
            CUDA_CHECK(cudaMemset(d_region_cycles, 0, sizeof(unsigned long long) * 2));
            CUDA_CHECK(cudaMemset(d_region_counts, 0, sizeof(unsigned long long) * 2));

            // NVTX host range for kernel launch (helps Nsight timeline)
#if __has_include(<nvToolsExt.h>)
#include <nvToolsExt.h>
#endif
#if defined(NVTX_EXT)
            nvtxRangePushA("brute_force_kernel_launch");
#endif
            brute_force_kernel<<<blocks, threads_per_block>>>(
                d_salt, params.salt.size(), params.iterations,
                d_nonce, params.iv.size(),
                d_encrypted, params.encrypted_data.size(),
                start, candidates_per_launch, d_found_flag, d_result_password,
                d_region_cycles, d_region_counts
            );
#if defined(NVTX_EXT)
            nvtxRangePop();
#endif

            // check kernel launch error immediately
            cudaError_t launchErr = cudaGetLastError();
            if (launchErr != cudaSuccess) {
                std::cerr << "Kernel launch error: " << cudaGetErrorString(launchErr) << std::endl;
                CUDA_CHECK(cudaFree(d_region_cycles));
                CUDA_CHECK(cudaFree(d_region_counts));
                break;
            }

            CUDA_CHECK(cudaDeviceSynchronize());

            // copy profiling counters back to host for this launch
            unsigned long long h_region_cycles[2];
            unsigned long long h_region_counts[2];
            CUDA_CHECK(cudaMemcpy(h_region_cycles, d_region_cycles, sizeof(unsigned long long) * 2, cudaMemcpyDeviceToHost));
            CUDA_CHECK(cudaMemcpy(h_region_counts, d_region_counts, sizeof(unsigned long long) * 2, cudaMemcpyDeviceToHost));
            CUDA_CHECK(cudaFree(d_region_cycles));
            CUDA_CHECK(cudaFree(d_region_counts));

            total_candidates_tested += candidates_per_launch;

            int found;
            CUDA_CHECK(cudaMemcpy(&found, d_found_flag, sizeof(int), cudaMemcpyDeviceToHost));
            if (found) {
                unsigned char result[56];
                CUDA_CHECK(cudaMemcpy(result, d_result_password, 56, cudaMemcpyDeviceToHost));
                std::ofstream ofs(output_file);
                if (!ofs) {
                    std::cerr << "Error opening output file: " << output_file << std::endl;
                    break;
                }
                ofs << "Password found: " << reinterpret_cast<char*>(result) << std::endl;
                ofs << std::endl;
                std::cout << "Password found and written to " << output_file << std::endl;
                break;
            }

            // report simple hotspot info for this launch
            // print host-side counts if available, only if profiling flag is set
            if (enable_profile && (h_region_counts[0] || h_region_counts[1])) {
                std::cout << "Launch profiling: PBKDF2 count=" << h_region_counts[0]
                          << " cycles=" << h_region_cycles[0]
                          << " | AES-CCM count=" << h_region_counts[1]
                          << " cycles=" << h_region_cycles[1] << std::endl;
            }
        }

        running = false;
        progress_thread.join();
        gpu_thread.join();

        CUDA_CHECK(cudaFree(d_salt));
        CUDA_CHECK(cudaFree(d_nonce));
        CUDA_CHECK(cudaFree(d_encrypted));
        CUDA_CHECK(cudaFree(d_found_flag));
        CUDA_CHECK(cudaFree(d_result_password));
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}