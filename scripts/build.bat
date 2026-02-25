@echo off
REM Build script for Windows
set SRC_DIR=src
set INCLUDE_DIR=include
set OUT=build\bitlocker_rpc.exe
set NVCC_FLAGS=-gencode arch=compute_XX,code=sm_XX -I%INCLUDE_DIR% -o %OUT%

nvcc %NVCC_FLAGS% %SRC_DIR%\bitlocker_rpc.cu %SRC_DIR%\hash_parser.cpp %SRC_DIR%\kernel.cu %SRC_DIR%\password_gen.cu %SRC_DIR%\utils.cpp ^
    %SRC_DIR%\crypto\aes_ccm.cu %SRC_DIR%\crypto\aes256.cu %SRC_DIR%\crypto\hmac_sha256.cu %SRC_DIR%\crypto\pbkdf2.cu %SRC_DIR%\crypto\sha256.cu
