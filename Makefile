# Makefile for RayPulse
# Wrapper around Meson build system with fallback manual build

BUILD_DIR := build
MESON_BUILD_DIR := $(BUILD_DIR)/meson

.PHONY: all setup compile run clean distclean help meson-build manual-build

# Default: try Meson first, fallback to manual build
all: setup
	@if [ -f "$(MESON_BUILD_DIR)/build.ninja" ]; then \
		$(MAKE) meson-build; \
	else \
		echo "Meson not configured, using manual build..."; \
		$(MAKE) manual-build; \
	fi

# Setup Meson build system
setup:
	@if command -v meson >/dev/null 2>&1; then \
		echo "Setting up Meson build..."; \
		meson setup $(MESON_BUILD_DIR) || true; \
	else \
		echo "Meson not found, will use manual build"; \
	fi

# Build using Meson
meson-build:
	@echo "Building with Meson..."
	meson compile -C $(MESON_BUILD_DIR)
	@if [ -f "$(MESON_BUILD_DIR)/raypulse" ]; then \
		cp $(MESON_BUILD_DIR)/raypulse $(BUILD_DIR)/raypulse; \
		echo "Executable: $(BUILD_DIR)/raypulse"; \
	fi
	@if [ -f "$(MESON_BUILD_DIR)/main.spv" ]; then \
		cp $(MESON_BUILD_DIR)/main.spv $(BUILD_DIR)/main.spv; \
		echo "Compute shader: $(BUILD_DIR)/main.spv"; \
	fi

# Manual build configuration (fallback)
CXX := g++
CC := gcc
CXXFLAGS := -std=c++17 -O2 -Wall -Wextra -Iinclude -Isrc/imgui -Isrc/imgui/backends -Isrc -Iexternal/glad/include -MMD -MP
CFLAGS := -O2 -Wall -Wextra -Iexternal/glad/include -MMD -MP

PKG_CFLAGS := $(shell pkg-config --cflags glfw3 2>/dev/null)
PKG_LIBS  := $(shell pkg-config --libs glfw3 2>/dev/null)
ifeq ($(strip $(PKG_LIBS)),)
  PKG_LIBS := -lglfw -lGL -ldl -lpthread -lX11 -lXrandr -lXi -lXxf86vm
endif

OPENEXR_LIBS := $(shell pkg-config --libs OpenEXR 2>/dev/null)
ifeq ($(strip $(OPENEXR_LIBS)),)
  OPENEXR_LIBS := -lIlmImf-2_5 -lImath-2_5 -lHalf-2_5 -lIex-2_5 -lIexMath-2_5 -lIlmThread-2_5
endif

CXXFLAGS += $(PKG_CFLAGS)
CFLAGS += $(PKG_CFLAGS)
LDFLAGS := $(PKG_LIBS) $(OPENEXR_LIBS)

SRCS := $(wildcard src/*.cpp)
IMGUI_SRCS := $(wildcard src/imgui/*.cpp src/imgui/backends/*.cpp)
GLAD_SRC := external/glad/src/gl.c

OBJ_DIR := $(BUILD_DIR)/obj
OBJS := $(SRCS:src/%.cpp=$(OBJ_DIR)/%.o)
IMGUI_OBJS := $(IMGUI_SRCS:src/%.cpp=$(OBJ_DIR)/%.o)
GLAD_OBJ := $(OBJ_DIR)/glad.o

ALL_OBJS := $(OBJS) $(IMGUI_OBJS) $(GLAD_OBJ)
DEPS := $(ALL_OBJS:.o=.d)

TARGET := $(BUILD_DIR)/raypulse
COMPUTE_SHADER := $(BUILD_DIR)/main.spv

manual-build: $(TARGET) $(COMPUTE_SHADER)
	@echo "Manual build complete: $(TARGET)"

$(COMPUTE_SHADER): shaders/compute/main.glsl shaders/compute/*.glsl
	@mkdir -p $(BUILD_DIR)
	@echo "Compiling compute shader..."
	@glslangValidator -G -S comp -Ishaders/compute $< -o $@ 2>/dev/null || \
		echo "Warning: Compute shader compilation failed (glslangValidator not found or shader errors)"

$(TARGET): $(ALL_OBJS)
	@mkdir -p $(BUILD_DIR)
	@echo "Linking $(TARGET)..."
	$(CXX) $(CXXFLAGS) -o $@ $^ $(LDFLAGS)

$(OBJ_DIR)/%.o: src/%.cpp
	@mkdir -p $(dir $@)
	@echo "Compiling $<..."
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(OBJ_DIR)/imgui/%.o: src/imgui/%.cpp
	@mkdir -p $(dir $@)
	@echo "Compiling $<..."
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(OBJ_DIR)/imgui/backends/%.o: src/imgui/backends/%.cpp
	@mkdir -p $(dir $@)
	@echo "Compiling $<..."
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(GLAD_OBJ): $(GLAD_SRC)
	@mkdir -p $(dir $@)
	@echo "Compiling GLAD..."
	$(CC) $(CFLAGS) -c $< -o $@

run: all
	@if [ -f "$(TARGET)" ]; then \
		echo "Running RayPulse..."; \
		./$(TARGET); \
	else \
		echo "Error: Executable not found. Run 'make' first."; \
	fi

clean:
	@echo "Cleaning build artifacts..."
	-rm -rf $(BUILD_DIR)/obj $(BUILD_DIR)/raypulse $(BUILD_DIR)/main.spv
	-rm -f $(DEPS)

distclean: clean
	@echo "Removing all build directories..."
	-rm -rf $(BUILD_DIR)

help:
	@echo "RayPulse Build System"
	@echo "====================="
	@echo ""
	@echo "Targets:"
	@echo "  make          Build the project (auto-detects Meson or manual)"
	@echo "  make setup    Configure Meson build system"
	@echo "  make run      Build and run the executable"
	@echo "  make clean    Remove build artifacts (keeps Meson config)"
	@echo "  make distclean Remove all build files including Meson"
	@echo "  make help     Show this help message"
	@echo ""
	@echo "Output:"
	@echo "  Executable:     build/raypulse"
	@echo "  Object files:   build/obj/"
	@echo "  Meson build:    build/meson/"

-include $(DEPS)
