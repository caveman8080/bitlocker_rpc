This Bitlocker Recovery Password cracker was made entirely with Grok.

To build:

nvcc -gencode arch=compute_##,code=sm_## -v -o bitlocker_rpc bitlocker_rpc.cu
* replace arch=compute_## and code-sm_## with the correct values for your GPU *

To run:

./bitlocker_rpc 'bitlocker recovery password hash'
* Use bitcracker to get your bitlocker recovery hash *
* Use ./bitlocker_rpc -h for more information *

Notes:
1. This program only supports one GPU. There is no option to select a GPU in a multi GPU setup.
