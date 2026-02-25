
![GPU Accelerated](https://img.shields.io/badge/GPU-CUDA-green)
![License](https://img.shields.io/badge/license-MIT-blue)

# BitLocker Recovery Password Cracker (bitlocker_rpc)

## Overview
BitLocker Recovery Password Cracker (bitlocker_rpc) is a GPU-accelerated brute-force tool for recovering BitLocker recovery passwords using NVIDIA CUDA. It leverages OpenSSL's bitcracker hash extraction and tests candidate passwords in parallel on your GPU.

## Features
- GPU-accelerated brute-force (CUDA)
- Supports bitcracker hash format
- Customizable thread/block configuration for performance tuning
- Progress and GPU utilization reporting
- Robust error handling and validation

## Installation
### Prerequisites
- NVIDIA GPU with CUDA support
- CUDA Toolkit installed
- C++ compiler (for host code)
- OpenSSL (for hash extraction via bitcracker)

### Build
1. Find your GPU compute capability:
	 - Run `nvidia-smi` and note the compute capability (e.g., 75 for RTX 2080)
2. Build the project:
	 - `nvcc -gencode arch=compute_##,code=sm_## -v -o bitlocker_rpc bitlocker_rpc.cu`
	 - Replace `##` with your GPU's compute capability

## Usage
### Basic Usage
- Run with hash as argument:
	- `./bitlocker_rpc 'HASH_STRING'`
- Run with hash from file:
	- `./bitlocker_rpc -f hash.txt`
- Custom thread/block config:
	- `./bitlocker_rpc -f hash.txt -t 512 -b 512`
- Output result to file:
	- `./bitlocker_rpc -f hash.txt -o out.txt`

### Hash Format
- Use bitcracker to extract your BitLocker hash
- Supported format:
	- `bitlocker$version$saltLen$saltHex$iterations$ivLen$ivHex$encryptedLen$encryptedHex`

### Options
- `-h`        Show help message
- `-f <file>` Input file containing BitLocker hash
- `-t <num>`  Threads per block (default: 256)
- `-b <num>`  Blocks (default: 256)
- `-o <file>` Output file for found password (default: found.txt)

## Contribution Guidelines
- Fork the repository and create a feature branch
- Submit pull requests with clear descriptions
- Follow C++ and CUDA best practices
- Add comments and documentation for new features
- Report issues via GitHub

## Notes
- Single GPU only; no multi-GPU support
- Hash files should use Unix-style line endings (LF)
- For troubleshooting, see error messages and logs
- For more info, run `./bitlocker_rpc -h`

## License
MIT License
