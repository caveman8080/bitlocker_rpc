/**
 * @file bitlocker_rpc.cu
 * @brief Main host entrypoint for GPU-accelerated BitLocker recovery password tester.
 *
 * Purpose: Parses CLI/hash, orchestrates multi-GPU brute-force using device-side password gen + crypto kernels.
 * Host responsibilities: CLI (getopt), hash parsing (BitCracker format), GPU discovery/keyspace split,
 *                       staging H->D transfers, launch loops, progress reporting, quit handling ('q' key),
 *                       result write if found.
 * Key algorithms:
 *   - Password space: 8x6-digit groups, each divisible by 11 (*11 checksum trick: 90,909 valid/group).
 *   - Mask mode: Fixed groups validated (%11==0), unknown brute-forced (index % 90909 *11).
 *   - Multi-GPU: Even split of total space (90909^unknown_count), per-GPU streams/async memcpy.
 *   - Benchmark: Password-gen only, 100M keys or 10s cap, reports Mkeys/s.
 *   - Quit: Atomic 'running' flag + cross-platform kbhit() poll in progress thread.
 *   - Found: Atomic flag + CAS claim, only one thread writes password to global result buffer.
 * Usage Qs answered: "Walk through cracking loop", "Why 90909?", "VMK magic?", "How to quit mid-run".
 */

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
#include <atomic>
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

std::atomic<bool> running = true;
unsigned long long total_candidates_tested = 0;
bool benchmark_mode = false;
std::string g_mask_str;
unsigned long long estimated_keyspace = 0;

// device symbols declared in password_gen.cu
extern __device__ unsigned int d_mask_fixed_vals[8];
extern __device__ unsigned char d_mask_fixed_flags[8];
extern __device__ int d_unknown_pos[8];
extern __device__ int d_unknown_count;

// Lightweight kernel that only calls the password generator and counts
// generated candidates. Keeps crypto paths untouched.
__global__ void password_gen_benchmark_kernel(unsigned long long start_index,
                                             unsigned long long candidates_per_launch,
                                             unsigned int *d_count) {
    unsigned long long gid = static_cast<unsigned long long>(blockIdx.x) * blockDim.x + threadIdx.x;
    unsigned long long total_threads = static_cast<unsigned long long>(gridDim.x) * blockDim.x;
    unsigned int local_count = 0u;
    for (unsigned long long offset = gid; offset < candidates_per_launch; offset += total_threads) {
        unsigned long long idx = start_index + offset;
        unsigned char pwd[56];
        generate_password(idx, pwd);
        ++local_count;
    }
    if (local_count) atomicAdd(d_count, local_count);
}

/**
 * @brief Print beautiful, comprehensive CLI help matching README.md.
 * Sections: Usage, Options (w/ defaults), Examples, Tips.
 * Answers all "CLI ?" questions for LLMs.
 */
void print_help(const char* exe_name) {
    std::cout << "\n" << exe_name << ": GPU-accelerated BitLocker Recovery Password Tester\n";
    std::cout << "================================================================\n\n";

    std::cout << "USAGE:\n";
    std::cout << "  " << exe_name << " [OPTIONS] [HASH_STRING]\n";
    std::cout << "  or -f FILE for hash from file.\n\n";

    std::cout << "OPTIONS:\n";
    std::cout << "  -h, --help             Show this help\n";
    std::cout << "  -f FILE                Hash from file\n";
    std::cout << "  -t N                   Threads/block (def: 256)\n";
    std::cout << "  -b N                   Blocks/grid (def: 256)\n";
    std::cout << "  -B, --benchmark        Benchmark gen (100M/10s)\n";
    std::cout << "  -o FILE                Output file (def: found.txt)\n";
    std::cout << "  -m MASK                55-char mask (? wild) (def: full)\n";
    std::cout << "  -d DEVS                GPUs comma-sep (def: all)\n";
    std::cout << "  --profile              Profiling output\n\n";

    std::cout << "EXAMPLES:\n";
    std::cout << "  " << exe_name << " -t 512 -b 1024 \"bitlocker$1$32$...\"\n";
    std::cout << "  " << exe_name << " -f hash.txt -m \"123456-??????-...\"\n";
    std::cout << "  " << exe_name << " -B -t 512 -b 1024  # Benchmark\n";
    std::cout << "  " << exe_name << " -d 0,1 -f hash.txt\n\n";

    std::cout << "TIPS:\n";
    std::cout << "  - Tune with -B first (monitor GPU util).\n";
    std::cout << "  - Press 'q' anytime to quit.\n";
    std::cout << "  - Mask: fixed groups %11==0, reduces to 90909^unknowns.\n";
    std::cout << "  - Hash: bitlocker$ver$saltlen$salt$iter$ivlen$iv$enc_len$enc\n\n";
}

/**
 * @brief Main entrypoint: CLI parsing, hash setup, GPU orchestration, brute-force or benchmark loop.
 *
 * Inputs: argv CLI flags (-f hashfile/t threads/b blocks/B bench/o out/m mask/d devs).
 * Outputs: found.txt with password if match, or benchmark stats.
 * Flow:
 *  1. Parse opts, read hash (inline/file).
 *  2. If mask: validate fixed (%11), compute keyspace=90909^unknowns, upload symbols.
 *  3. Benchmark: loop gen_kernel until 100M/10s.
 *  4. Brute: Parse hash->salt/iv/enc/iter, discover GPUs, split space, alloc per-GPU bufs/streams.
 *  5. Loop: Launch kernel chunks async, sync, check atomic found_flag, copy pwd if claimed.
 *  6. Progress/GPU util threads: Live stats, kbhit 'q'->running=false.
 * Thread safety: atomic<bool> running, per-GPU ctx, atomic found_flag/CAS.
 * Perf: Tunable grid (blocks x threads), stride indexing for parallelism.
 */
int main(int argc, char* argv[]) {
    std::string hash_str;
    std::string input_file;
    std::string output_file = "found.txt";
    int threads_per_block = 256;
    int blocks = 256;

    int opt;
    bool enable_profile = false;
    std::string devices_str;
    g_mask_str.clear();  // global
    while ((opt = getopt(argc, argv, "hf:t:b:Bo:m:d:")) != -1) {  // Note: added : for o
        switch (opt) {
            case 'h':
                print_help(argv[0]);
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
            case 'm':
                g_mask_str = optarg;
                break;
            case 'd':
                devices_str = optarg;
                break;
            case 'B':
                benchmark_mode = true;
                break;
            default:
                std::cerr << "Unknown option: -" << static_cast<char>(optopt) << "\n";
                print_help(argv[0]);
                return 1;
        }
    }

    if (!benchmark_mode) {
        if (!input_file.empty()) {
            std::ifstream ifs(input_file);
            if (!ifs) {
                std::cerr << "Error opening input file: " << input_file << std::endl;
                return 1;
            }
            std::stringstream ss;
            ss << ifs.rdbuf();
            hash_str = ss.str();
            if (!hash_str.empty() && hash_str.back() == '\n') hash_str.pop_back();
        } else if (optind < argc) {
            hash_str = argv[optind];
        } else {
            std::cerr << "No hash provided.\n";
            print_help(argv[0]);
            return 1;
        }
    }

    try {
        // If a mask was provided, validate and copy mask data to device symbols
        if (!g_mask_str.empty()) {
            // validate length: 8 groups of 6 + 7 hyphens = 55
            if (g_mask_str.size() != 55) {
                std::cerr << "Invalid mask length; expected 8 groups of 6 digits separated by hyphens." << std::endl;
                return 1;
            }
            unsigned int host_fixed_vals[8] = {0};
            unsigned char host_fixed_flags[8] = {0};
            int host_unknown_pos[8] = {0};
            int unknown_count = 0;
            for (int g = 0; g < 8; ++g) {
                int off = g * 7;
                bool any_q = false;
                unsigned int val = 0;
                for (int d = 0; d < 6; ++d) {
                    char c = g_mask_str[off + d];
                    if (c == '?') any_q = true;
                    else if (c >= '0' && c <= '9') {
                        val = val * 10u + static_cast<unsigned int>(c - '0');
                    } else {
                        std::cerr << "Invalid character in mask." << std::endl;
                        return 1;
                    }
                }
                if (g < 7) {
                    if (g_mask_str[off + 6] != '-') { std::cerr << "Invalid mask format (missing hyphen)." << std::endl; return 1; }
                }
                if (!any_q) {
                    // fixed group: must be divisible by 11
                    if (val % 11u != 0u) { std::cerr << "Mask group not divisible by 11: group " << g << std::endl; return 1; }
                    host_fixed_vals[g] = val;
                    host_fixed_flags[g] = 1;
                } else {
                    host_fixed_flags[g] = 0;
                    host_unknown_pos[unknown_count++] = g;
                }
            }
            // copy to device symbols
            CUDA_CHECK(cudaMemcpyToSymbol(d_mask_fixed_vals, host_fixed_vals, sizeof(host_fixed_vals)));
            CUDA_CHECK(cudaMemcpyToSymbol(d_mask_fixed_flags, host_fixed_flags, sizeof(host_fixed_flags)));
            CUDA_CHECK(cudaMemcpyToSymbol(d_unknown_pos, host_unknown_pos, sizeof(host_unknown_pos)));
            CUDA_CHECK(cudaMemcpyToSymbol(d_unknown_count, &unknown_count, sizeof(int)));

            // compute estimated keyspace: PER_GROUP^unknown_count
            unsigned long long keyspace = 1ULL;
            for (int i = 0; i < unknown_count; ++i) keyspace *= 90909ULL;
            estimated_keyspace = keyspace;
        }

        if (benchmark_mode) {
            // Benchmark: Password generation throughput only (no crypto/hash).
            // Tests kernel launch overhead + gen speed. 100M cands or 10s cap.
            // Precise GPU timing w/ cudaEvent. Reports Mkeys/s.
            // Single GPU (default device); multi-GPU bench extension future.
            unsigned long long target = 100000000ULL; // 100M candidates
            unsigned long long candidates_per_launch = static_cast<unsigned long long>(blocks) * threads_per_block;

            // Progress + GPU util threads (live speed via total_candidates_tested)
            std::thread progress_thread(display_progress);
            std::thread gpu_thread(display_gpu_utilization);

            // GPU counter + events for precise elapsed
            unsigned int *d_count;
            cudaEvent_t start_event, stop_event;
            CUDA_CHECK(cudaMalloc(&d_count, sizeof(unsigned int)));
            CUDA_CHECK(cudaMemset(d_count, 0, sizeof(unsigned int)));
            CUDA_CHECK(cudaEventCreate(&start_event));
            CUDA_CHECK(cudaEventCreate(&stop_event));
            CUDA_CHECK(cudaEventRecord(start_event, 0));  // Default stream

            auto t0_host = std::chrono::high_resolution_clock::now();  // Host safety cap
            while (running.load() && total_candidates_tested < target) {
                unsigned long long start_index = total_candidates_tested;
                password_gen_benchmark_kernel<<<blocks, threads_per_block>>>(start_index, candidates_per_launch, d_count);
                CUDA_CHECK(cudaDeviceSynchronize());  // Block for count

                unsigned int h_count;
                CUDA_CHECK(cudaMemcpy(&h_count, d_count, sizeof(unsigned int), cudaMemcpyDeviceToHost));
                total_candidates_tested = h_count;  // Atomic accum

                auto now_host = std::chrono::high_resolution_clock::now();
                double elapsed_host = std::chrono::duration_cast<std::chrono::duration<double>>(now_host - t0_host).count();
                if (elapsed_host >= 10.0) break;  // 10s host cap
            }

            CUDA_CHECK(cudaEventRecord(stop_event, 0));
            CUDA_CHECK(cudaEventSynchronize(stop_event));
            float gpu_elapsed_ms;
            CUDA_CHECK(cudaEventElapsedTime(&gpu_elapsed_ms, start_event, stop_event));
            double gpu_elapsed = gpu_elapsed_ms / 1000.0;

            int dev_id;
            cudaGetDevice(&dev_id);

            double keys_per_sec = static_cast<double>(total_candidates_tested) / gpu_elapsed;
            std::cout << "\nBenchmark complete: "
                      << std::fixed << std::setprecision(2)
                      << (keys_per_sec / 1e6) << " M keys/sec on GPU " << dev_id
                      << " (GPU time: " << gpu_elapsed << "s, " << total_candidates_tested << " cands)\n";

            running.store(false);
            progress_thread.join();
            gpu_thread.join();
            CUDA_CHECK(cudaFree(d_count));
            CUDA_CHECK(cudaEventDestroy(start_event));
            CUDA_CHECK(cudaEventDestroy(stop_event));
            return 0;
        }

        // Normal path: parse hash and run full brute-force kernel (multi-GPU aware)
        HashParams params = parse_hash(hash_str);

        // Discover devices
        int device_count = 0;
        CUDA_CHECK(cudaGetDeviceCount(&device_count));
        if (device_count <= 0) {
            std::cerr << "No CUDA devices found." << std::endl;
            return 1;
        }

        // Build selected device list
        std::vector<int> selected_devices;
        if (devices_str.empty()) {
            for (int i = 0; i < device_count; ++i) selected_devices.push_back(i);
        } else {
            std::stringstream ss(devices_str);
            std::string token;
            while (std::getline(ss, token, ',')) {
                int id = std::atoi(token.c_str());
                if (id < 0 || id >= device_count) { std::cerr << "Invalid device id: " << id << std::endl; return 1; }
                selected_devices.push_back(id);
            }
        }

        int ngpus = static_cast<int>(selected_devices.size());

        // Print device list and a very rough perf estimate
        double total_est = 0.0;
        std::ostringstream devs_out;
        for (size_t i = 0; i < selected_devices.size(); ++i) {
            int did = selected_devices[i];
            cudaDeviceProp prop;
            CUDA_CHECK(cudaGetDeviceProperties(&prop, did));
            if (i) devs_out << ", ";
            devs_out << did << " (" << prop.name << ")";
            // crude estimate: use SM count as a relative performance proxy
            total_est += static_cast<double>(prop.multiProcessorCount);
        }
        // normalize to GH/s estimate
        double ghps = total_est * 0.05; // very rough: ~0.05 GH/s per SM
        std::cout << "Using GPUs: " << devs_out.str() << " – total " << std::fixed << std::setprecision(2) << ghps << " GH/s expected" << std::endl;

        unsigned long long candidates_per_launch = static_cast<unsigned long long>(blocks) * threads_per_block;

        // per-GPU context
        struct GPUCtx {
            int dev;
            cudaStream_t stream;
            unsigned char *d_salt, *d_nonce, *d_encrypted, *d_result_password;
            int *d_found_flag;
            unsigned long long *d_region_cycles;
            unsigned long long *d_region_counts;
            unsigned int *d_count_bench;
            unsigned long long start;
            unsigned long long end;
            unsigned long long next;
        };

        std::vector<GPUCtx> gpus;
        gpus.reserve(ngpus);

        // compute global max index (use estimated_keyspace if present)
        unsigned long long max_index = 1ULL;
        bool overflowed = false;
        if (estimated_keyspace > 0) max_index = estimated_keyspace;
        else {
            for (int i = 0; i < 8; i++) {
                if (max_index > ULLONG_MAX / 90909ULL) { overflowed = true; max_index = ULLONG_MAX; break; }
                max_index *= 90909ULL;
            }
        }

        // split keyspace evenly
        unsigned long long base_chunk = max_index / ngpus;
        unsigned long long rem = max_index % ngpus;

        for (int i = 0; i < ngpus; ++i) {
            GPUCtx ctx = {};
            ctx.dev = selected_devices[i];
            ctx.start = i == 0 ? 0ULL : (base_chunk * i + (i <= (int)rem ? i : rem));
            ctx.end = ctx.start + base_chunk + (i < (int)rem ? 1ULL : 0ULL);
            ctx.next = ctx.start;
            CUDA_CHECK(cudaSetDevice(ctx.dev));
            CUDA_CHECK(cudaStreamCreate(&ctx.stream));
            // allocate per-GPU buffers
            CUDA_CHECK(cudaMalloc(&ctx.d_salt, params.salt.size()));
            CUDA_CHECK(cudaMalloc(&ctx.d_nonce, params.iv.size()));
            CUDA_CHECK(cudaMalloc(&ctx.d_encrypted, params.encrypted_data.size()));
            CUDA_CHECK(cudaMalloc(&ctx.d_found_flag, sizeof(int)));
            CUDA_CHECK(cudaMalloc(&ctx.d_result_password, 56));
            CUDA_CHECK(cudaMalloc(&ctx.d_region_cycles, sizeof(unsigned long long) * 2));
            CUDA_CHECK(cudaMalloc(&ctx.d_region_counts, sizeof(unsigned long long) * 2));
            CUDA_CHECK(cudaMemset(ctx.d_region_cycles, 0, sizeof(unsigned long long) * 2));
            CUDA_CHECK(cudaMemset(ctx.d_region_counts, 0, sizeof(unsigned long long) * 2));
            CUDA_CHECK(cudaMemcpyAsync(ctx.d_salt, params.salt.data(), params.salt.size(), cudaMemcpyHostToDevice, ctx.stream));
            CUDA_CHECK(cudaMemcpyAsync(ctx.d_nonce, params.iv.data(), params.iv.size(), cudaMemcpyHostToDevice, ctx.stream));
            CUDA_CHECK(cudaMemcpyAsync(ctx.d_encrypted, params.encrypted_data.data(), params.encrypted_data.size(), cudaMemcpyHostToDevice, ctx.stream));
            CUDA_CHECK(cudaMemsetAsync(ctx.d_found_flag, 0, sizeof(int), ctx.stream));
            if (benchmark_mode) {
                CUDA_CHECK(cudaMalloc(&ctx.d_count_bench, sizeof(unsigned int)));
                CUDA_CHECK(cudaMemsetAsync(ctx.d_count_bench, 0, sizeof(unsigned int), ctx.stream));
            } else ctx.d_count_bench = nullptr;
            gpus.push_back(ctx);
        }

        // start progress thread
        std::thread progress_thread(display_progress);
        std::thread gpu_thread(display_gpu_utilization);

        // launch/iterate across GPUs until done or found
        bool any_active = true;
        while (running.load() && any_active) {
            any_active = false;
            // launch next chunk on each GPU
            for (auto &ctx : gpus) {
                if (ctx.next >= ctx.end) continue;
                any_active = true;
                CUDA_CHECK(cudaSetDevice(ctx.dev));
                unsigned long long remaining = ctx.end - ctx.next;
                unsigned long long this_launch = remaining < candidates_per_launch ? remaining : candidates_per_launch;
                if (benchmark_mode) {
                    password_gen_benchmark_kernel<<<blocks, threads_per_block, 0, ctx.stream>>>(ctx.next, this_launch, ctx.d_count_bench);
                } else {
#if __has_include(<nvToolsExt.h>)
#include <nvToolsExt.h>
#endif
#if defined(NVTX_EXT)
                    nvtxRangePushA("brute_force_kernel_launch");
#endif
                    brute_force_kernel<<<blocks, threads_per_block, 0, ctx.stream>>>(
                        ctx.d_salt, params.salt.size(), params.iterations,
                        ctx.d_nonce, params.iv.size(),
                        ctx.d_encrypted, params.encrypted_data.size(),
                        ctx.next, this_launch, ctx.d_found_flag, ctx.d_result_password,
                        ctx.d_region_cycles, ctx.d_region_counts
                    );
#if defined(NVTX_EXT)
                    nvtxRangePop();
#endif
                }
                ctx.next += this_launch;
            }

            // synchronize and collect results per GPU
            for (auto &ctx : gpus) {
                CUDA_CHECK(cudaSetDevice(ctx.dev));
                CUDA_CHECK(cudaStreamSynchronize(ctx.stream));
                if (benchmark_mode) {
                    unsigned int h_count = 0;
                    CUDA_CHECK(cudaMemcpy(&h_count, ctx.d_count_bench, sizeof(unsigned int), cudaMemcpyDeviceToHost));
                    total_candidates_tested = h_count; // keep latest total (approx)
                } else {
                    // add candidates tested this round (we used ctx.next increments)
                    // For simplicity, increase total by candidates_per_launch or last chunk size
                    // (approximate aggregate)
                    // Could read region counts for more accuracy
                    // No-op here because ctx.next advanced already reflects work done; we'll sum below
                }

                int found = 0;
                CUDA_CHECK(cudaMemcpy(&found, ctx.d_found_flag, sizeof(int), cudaMemcpyDeviceToHost));
                if (found) {
                    unsigned char result[56];
                    CUDA_CHECK(cudaMemcpy(result, ctx.d_result_password, 56, cudaMemcpyDeviceToHost));
                    std::ofstream ofs(output_file);
                    if (!ofs) std::cerr << "Error opening output file: " << output_file << std::endl;
                    else {
                        ofs << "Password found: " << reinterpret_cast<char*>(result) << std::endl;
                        std::cout << "Password found and written to " << output_file << std::endl;
                    }
                    running.store(false);
                    break;
                }
            }

            // recompute aggregated total_candidates_tested from per-GPU progress
            unsigned long long agg = 0ULL;
            for (auto &ctx : gpus) agg += (ctx.next - ctx.start);
            total_candidates_tested = agg;
        }

        // cleanup per-GPU
        for (auto &ctx : gpus) {
            CUDA_CHECK(cudaSetDevice(ctx.dev));
            if (ctx.d_region_cycles) CUDA_CHECK(cudaFree(ctx.d_region_cycles));
            if (ctx.d_region_counts) CUDA_CHECK(cudaFree(ctx.d_region_counts));
            if (ctx.d_salt) CUDA_CHECK(cudaFree(ctx.d_salt));
            if (ctx.d_nonce) CUDA_CHECK(cudaFree(ctx.d_nonce));
            if (ctx.d_encrypted) CUDA_CHECK(cudaFree(ctx.d_encrypted));
            if (ctx.d_found_flag) CUDA_CHECK(cudaFree(ctx.d_found_flag));
            if (ctx.d_result_password) CUDA_CHECK(cudaFree(ctx.d_result_password));
            if (ctx.d_count_bench) CUDA_CHECK(cudaFree(ctx.d_count_bench));
            CUDA_CHECK(cudaStreamDestroy(ctx.stream));
        }

        running.store(false);
        progress_thread.join();
        gpu_thread.join();
    } catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << std::endl;
        return 1;
    }

    return 0;
}
