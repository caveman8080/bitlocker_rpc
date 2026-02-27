@echo off
REM Build script for Windows
set SRC_DIR=src
set INCLUDE_DIR=%SRC_DIR%\include
set OUT=build\bitlocker_rpc.exe
rem Detect GPU compute capability automatically if SM is not set
if "%SM%"=="" (
    for /f "tokens=2 delims=: " %%A in ('nvidia-smi --query-gpu=compute_cap --format=csv,noheader') do set SM=%%A
    rem Remove dot from compute capability (e.g., 7.5 -> 75)
    set SM=%SM:.=%
    rem If detection fails, fallback to 75
    if "%SM%"=="" set SM=75
)

rem ensure build directory exists
if not exist build mkdir build

rem NVCC flags: gencode for chosen SM, enable relocatable device code for cross-TU device calls
set NVCC_FLAGS=-gencode arch=compute_%SM%,code=sm_%SM% -gencode arch=compute_%SM%,code=compute_%SM% -I%INCLUDE_DIR% -I%SRC_DIR% -rdc=true -lineinfo -O3 -o %OUT%

nvcc %NVCC_FLAGS% %SRC_DIR%\bitlocker_rpc.cu %SRC_DIR%\hash_parser.cpp %SRC_DIR%\kernel.cu %SRC_DIR%\password_gen.cu %SRC_DIR%\utils.cpp ^
    %SRC_DIR%\getopt.c ^
    %SRC_DIR%\crypto\aes_ccm.cu %SRC_DIR%\crypto\aes128.cu %SRC_DIR%\crypto\aes256.cu %SRC_DIR%\crypto\hmac_sha256.cu %SRC_DIR%\crypto\pbkdf2.cu %SRC_DIR%\crypto\sha256.cu
