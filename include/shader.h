#pragma once
#include <string>
#include <vector>
#include <glad/gl.h>

GLuint compileShader(GLenum type, const GLchar* source);
GLuint compileShaderFromFile(GLenum type, const char* filepath);
GLuint createShaderProgram(const GLchar* vertexSource, const GLchar* fragmentSource);
GLuint createShaderProgramFromFiles(const char* vertPath, const char* fragPath);
GLuint createComputeProgramFromBinary(const char* binaryPath);