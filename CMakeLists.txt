# Specify the minimum version of CMake required
cmake_minimum_required(VERSION 3.10)

# Define the project name
project(RayPulse C)  # Specify 'C' as the language

# Set the C standard (optional, e.g., C99 or C11)
set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED True)

# Add the executable target
# Replace 'main.c' with your actual source files
add_executable(RayPulse src/main.c)  # You can list additional source files separated by spaces

target_link_libraries(RayPulse m)
# Optionally, specify include directories
# include_directories(include)  # Uncomment if you have an 'include' directory for header files

# If you have more source files, you can use the following method to include them
# file(GLOB SOURCES "src/*.c")  # Adjust the path as needed
# add_executable(RayPulse ${SOURCES})
