# Project settings
cmake_minimum_required(VERSION 3.10)
project(OpenGLProject)

# Set the C standard
set(CMAKE_C_STANDARD 99)

# Specify the source files
set(SOURCES src/main.c)

# Find OpenGL and GLFW
find_package(OpenGL REQUIRED)
find_package(glfw3 REQUIRED)

# Add the executable
add_executable(${PROJECT_NAME} ${SOURCES})

# Link the libraries
target_link_libraries(${PROJECT_NAME} OpenGL::GL glfw)
target_link_libraries(${PROJECT_NAME} m)