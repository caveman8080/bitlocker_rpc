#!/bin/bash
# Build script for Linux
SRC_DIR=src
INCLUDE_DIR=include
OUT=build/bitlocker_rpc
NVCC_FLAGS="-gencode arch=compute_XX,code=sm_XX -I$INCLUDE_DIR -o $OUT"

SM=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader | head -n1 | tr -d '.')
if [ -z "$SM" ]; then
    SM=75
fi
NVCC_FLAGS="-gencode arch=compute_$SM,code=sm_$SM -I$INCLUDE_DIR -o $OUT"

nvcc $NVCC_FLAGS $SRC_DIR/bitlocker_rpc.cu $SRC_DIR/hash_parser.cpp $SRC_DIR/kernel.cu $SRC_DIR/password_gen.cu $SRC_DIR/utils.cpp \
    $SRC_DIR/crypto/aes_ccm.cu $SRC_DIR/crypto/aes256.cu $SRC_DIR/crypto/hmac_sha256.cu $SRC_DIR/crypto/pbkdf2.cu $SRC_DIR/crypto/sha256.cu
