# 🌌 RayPulse - A Custom Ray Tracer in C with OpenGL 🌌

Welcome to **RayPulse**, a custom-built ray tracing engine designed in **C** using the **OpenGL** library. This project aims to deliver high-quality rendering, simulating light interactions with objects in a virtual 3D space.

## 📑 Table of Contents

- [🎯 Project Goals](#project-goals)
- [✨ Features](#features)
- [🛠 Requirements](#requirements)
- [📥 Installation](#installation)
- [🚀 Usage](#usage)
- [📂 Structure](#structure)
- [🔮 Future Enhancements](#future-enhancements)

## 🎯 Project Goals

This project is developed to:
- Gain a deeper understanding of ray tracing principles.
- Implement core graphics and shading techniques.
- Explore the capabilities of OpenGL for handling graphics in C.

## ✨ Features

- **🌟 Realistic Lighting**: Light interactions using basic Phong shading.
- **🔹 Object Rendering**: Rendering of spheres, planes, and other primitives.
- **🔮 Reflection and Refraction**: Basic reflection/refraction calculations for realistic effects.
- **🎥 Camera Control**: Adjustable camera for perspective and view angle settings.
- **🖼 Scene Customization**: Ability to add multiple objects, lights, and surfaces.

## 🛠 Requirements

To run and develop this ray tracer, you’ll need:

- **C Compiler**: GCC or Clang recommended.
- **OpenGL**: Ensure OpenGL is installed on your system.
- **GLFW**: For window and context management.
- **GLM**: OpenGL Mathematics library for vector and matrix calculations.
- **GLEW** (optional): For managing OpenGL extensions.

## 📥 Installation

1. **📂 Clone the repository**:
    ```bash
    git clone https://github.com/yourusername/RayTracer.git
    cd RayTracer
    ```

2. **📦 Install dependencies**:
    - For Ubuntu/Debian:
      ```bash
      sudo apt-get update
      sudo apt-get install libglfw3-dev libglm-dev libglew-dev
      ```
    - For macOS:
      ```bash
      brew install glfw glm glew
      ```

3. **🛠 Build the project**:
    ```bash
    make
    ```

## 🚀 Usage

1. **Run the Ray Tracer**:
    ```bash
    ./raytracer
    ```

2. **🎮 Controls**:
    - **WASD**: Move camera.
    - **Arrow Keys**: Adjust view angle.
    - **+/-**: Zoom in/out.

3. **🛠 Customization**: Modify the `scene.c` file to add or adjust objects and lights in the scene.

## 📂 Structure

The project’s main structure is as follows:

```plaintext
RayTracer/
├── src/
│   ├── main.c            # Program entry point
│   ├── renderer.c        # Core rendering loop and OpenGL setup
│   ├── ray_tracer.c      # Ray tracing calculations
│   ├── scene.c           # Scene setup and object definitions
│   └── shaders/          # OpenGL shaders for lighting and effects
├── include/
│   ├── ray_tracer.h      # Ray tracing header
│   ├── renderer.h        # Renderer header
│   └── scene.h           # Scene header
├── assets/               # Textures or additional assets
└── README.md

## 🔮 Future Enhancements

- **✨ Additional Shading Models**: Implement other shading models, such as Blinn-Phong and Lambertian shading.
- **🔍 Anti-Aliasing**: Apply super-sampling to smooth jagged edges.
- **⚡ Multithreading**: Improve rendering speed with parallel computation.
- **🌈 Advanced Features**: Consider adding shadows, depth of field, or global illumination.

## 📜 License

This project is open-source and available under the [MIT License](LICENSE).

