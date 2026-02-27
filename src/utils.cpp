// Utility functions implementation
// Extracted from bitlocker_rpc.cu
#include "utils.h"
#include <thread>
#include <chrono>
#include <iostream>
#include <iomanip>
#include <string>
#include <mutex>
#include <atomic>
#include <cctype>
#include <sstream>
#ifdef _WIN32
#include <conio.h>
#include <Windows.h>
#else
#include <termios.h>
#include <unistd.h>
#include <sys/select.h>
#endif

extern bool running;
extern unsigned long long total_candidates_tested;

void display_progress() {
    using namespace std::chrono_literals;
    auto start_time = std::chrono::steady_clock::now();
    unsigned long long last_tested = 0;
    // Use a single-line in-place stats update to avoid multi-line cursor issues
    std::cout << "\nBitLocker RPC - GPU Brute Force Recovery\n";
    std::cout << "----------------------------------------\n";
    std::cout << "(Q)uit\n";
    // reserve one line for in-place stats
    std::cout << "\n";
    std::cout << std::flush;
    // input state (centralized polling in main loop)
    bool native_raw = false;
#ifdef _WIN32
    // Try enabling Windows console raw mode (disable line input and echo)
    HANDLE hStdin = GetStdHandle(STD_INPUT_HANDLE);
    DWORD origMode = 0;
    if (hStdin != INVALID_HANDLE_VALUE && GetConsoleMode(hStdin, &origMode)) {
        DWORD rawMode = origMode & ~(ENABLE_LINE_INPUT | ENABLE_ECHO_INPUT);
        if (SetConsoleMode(hStdin, rawMode)) native_raw = true;
    }
#else
    // Try enabling POSIX raw mode (non-canonical, no echo)
    struct termios orig_termios;
    if (tcgetattr(STDIN_FILENO, &orig_termios) == 0) {
        struct termios raw = orig_termios;
        raw.c_lflag &= ~(ICANON | ECHO);
        if (tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) == 0) native_raw = true;
    }
#endif

    // helper to read a single character when in native raw mode
    auto read_single_char = [&]() -> char {
#ifdef _WIN32
        return static_cast<char>(_getch());
#else
        char c = 0;
        ssize_t r = read(STDIN_FILENO, &c, 1);
        if (r <= 0) return 0;
        return c;
#endif
    };

#ifndef _WIN32
    // include select for POSIX input polling
    // (select declared in sys/select.h but unistd.h is already included)
#endif

    while (running) {
        auto now = std::chrono::steady_clock::now();
        unsigned long long tested = total_candidates_tested;
        double elapsed = std::chrono::duration_cast<std::chrono::seconds>(now - start_time).count();
        double speed = elapsed > 0 ? (tested / elapsed) : 0;
        double progress = 0.0; // TODO: set actual progress percentage if max_index is available
        double utilization = 98.0; // Placeholder, real value from GPU stats if available
        double eta = speed > 0 ? ((100.0 - progress) * elapsed / (progress > 0 ? progress : 1)) : 0;

          // Build one-line stats string and print in-place
          std::ostringstream stats;
          stats << "Candidates:" << tested << " | "
              << "Speed:" << static_cast<unsigned long long>(speed) << " c/s | "
              << "Elapsed:" << std::setw(2) << std::setfill('0') << static_cast<int>(elapsed/3600) << ":"
              << std::setw(2) << std::setfill('0') << static_cast<int>((static_cast<int>(elapsed)/60)%60) << ":"
              << std::setw(2) << std::setfill('0') << static_cast<int>(static_cast<int>(elapsed)%60) << " | "
              << "Progress:" << std::fixed << std::setprecision(2) << progress << "% | "
              << "Util:" << utilization << "% | "
              << "ETA:" << std::setw(2) << std::setfill('0') << static_cast<int>(eta/3600) << ":"
              << std::setw(2) << std::setfill('0') << static_cast<int>((static_cast<int>(eta)/60)%60) << ":"
              << std::setw(2) << std::setfill('0') << static_cast<int>(static_cast<int>(eta)%60);
        std::string s = stats.str();
        // helper to move cursor up one line and clear it (platform-specific)
        auto move_up_and_clear = [&]() {
#ifdef _WIN32
            HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);
            if (hOut != INVALID_HANDLE_VALUE) {
                CONSOLE_SCREEN_BUFFER_INFO csbi;
                if (GetConsoleScreenBufferInfo(hOut, &csbi)) {
                    COORD pos = csbi.dwCursorPosition;
                    if (pos.Y > 0) pos.Y -= 1;
                    pos.X = 0;
                    DWORD written = 0;
                    DWORD width = csbi.dwSize.X;
                    SetConsoleCursorPosition(hOut, pos);
                    FillConsoleOutputCharacterA(hOut, ' ', width, pos, &written);
                    FillConsoleOutputAttribute(hOut, csbi.wAttributes, width, pos, &written);
                    SetConsoleCursorPosition(hOut, pos);
                }
            }
#else
            std::cout << "\033[1A\033[2K";
#endif
        };
        move_up_and_clear();
        std::cout << s << std::endl << std::flush;
        // Centralized input polling: on Windows use only _kbhit()/_getch() for both
        // the 'q' detection and the y/n confirmation to avoid std::cin buffering issues.
#ifdef _WIN32
        if (_kbhit()) {
            char ch = static_cast<char>(_getch());
            if (ch == 'q' || ch == 'Q') {
                std::cout << "\nExit the program (y/n)? " << std::flush;
                char confirm = static_cast<char>(_getch());
                std::cout << confirm << std::endl;  // echo the choice for the user
                if (confirm == 'y' || confirm == 'Y') {
                    std::cout << "Exiting gracefully...\n" << std::flush;
                    running = false;  // set global flag to stop threads/loop
                } else {
                    std::cout << "Continuing...\n" << std::flush;
                }
            }
        }
#else
        if (native_raw) {
            // non-blocking read already enabled via termios raw mode
            // use read to pull one char
            char c = 0;
            ssize_t r = read(STDIN_FILENO, &c, 1);
            if (r > 0) {
                if (c == 'q' || c == 'Q') {
                    std::cout << "\nExit program (y/n): " << std::flush;
                    std::this_thread::sleep_for(300ms);
                    char cc = read_single_char();
                    if (cc == 'y' || cc == 'Y') running = false;
                    else {
                        std::cout << "\nContinuing...\n";
                        std::this_thread::sleep_for(300ms);
                        std::cout << "\033[2K\r" << std::flush;
                    }
                }
            }
        } else {
            // use select to poll stdin for a full line (Enter pressed)
            fd_set readfds;
            FD_ZERO(&readfds);
            FD_SET(STDIN_FILENO, &readfds);
            struct timeval tv;
            tv.tv_sec = 0;
            tv.tv_usec = 0;
            int ret = select(STDIN_FILENO + 1, &readfds, NULL, NULL, &tv);
            if (ret > 0 && FD_ISSET(STDIN_FILENO, &readfds)) {
                std::string line;
                if (std::getline(std::cin, line)) {
                    if (!line.empty() && (line[0] == 'q' || line[0] == 'Q')) {
                        std::cout << "\nExit program (y/n): " << std::flush;
                        std::this_thread::sleep_for(300ms);
                        std::string confirm;
                        if (std::getline(std::cin, confirm)) {
                            if (!confirm.empty() && (confirm[0] == 'y' || confirm[0] == 'Y')) running = false;
                            else {
                                std::cout << "\nContinuing...\n";
                                std::this_thread::sleep_for(300ms);
                                std::cout << "\033[2K\r" << std::flush;
                            }
                        }
                    }
                }
            }
        }
#endif
        last_tested = tested;
        std::this_thread::sleep_for(10s);
    }
    // restore terminal modes
#ifdef _WIN32
    if (native_raw && hStdin != INVALID_HANDLE_VALUE) {
        SetConsoleMode(hStdin, origMode);
    }
#else
    if (native_raw) {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &orig_termios);
    }
#endif
}

void display_gpu_utilization() {
    using namespace std::chrono_literals;
    while (running) {
        // Minimal placeholder: real implementation could call nvidia-smi or NVML.
        std::this_thread::sleep_for(5s);
    }
}
