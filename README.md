# 🌌 RayPulse - A Custom Ray Tracer in Modern C++ with OpenGL 🌌

Welcome to **RayPulse**, a custom-built ray tracing engine designed in **C++** using **OpenGL**. This project demonstrates foundational ray tracing concepts and integrates with OpenGL for future real-time rendering.

---

## 📑 Table of Contents

- [🌌 RayPulse - A Custom Ray Tracer in Modern C++ with OpenGL 🌌](#-raypulse---a-custom-ray-tracer-in-modern-c-with-opengl-)
  - [📑 Table of Contents](#-table-of-contents)
  - [🎯 Project Goals](#-project-goals)
  - [✨ Features](#-features)
  - [🛠 Requirements](#-requirements)
  - [📥 Installation \& Build](#-installation--build)
  - [🚀 Usage](#-usage)
  - [📂 Structure](#-structure)
  - [🔮 Future Enhancements](#-future-enhancements)
  - [📜 License](#-license)

---

## 🎯 Project Goals

- Learn and demonstrate ray tracing principles in C++.
- Build a modular, extensible codebase for experimenting with rendering techniques.
- Lay the groundwork for real-time ray tracing with OpenGL.

---

## ✨ Features

- **PPM Image Output**: Renders ray-traced images to PPM format.
- **Basic Ray Tracing**: Sphere intersection, background gradient, and surface normals visualization.
- **C++ Modern Design**: Uses classes, operator overloading, and header-only math utilities.
- **OpenGL Integration**: Ready for real-time rendering and shader-based extensions.
- **Progress Feedback**: Shows rendering progress in the terminal.

---

## 🛠 Requirements

- **C++ Compiler**: GCC or Clang with C++17 support.
- **Meson Build System**: For easy and modern project builds.
- **OpenGL**: Graphics library.
- **GLFW**: Window/context management.
- **GLEW**: OpenGL extension wrangler.

**Install dependencies (Ubuntu/Debian):**
```bash
sudo apt-get update
sudo apt-get install build-essential meson libglfw3-dev libglew-dev libglm-dev
```

---

## 📥 Installation & Build

1. **Clone the repository:**
    ```bash
    git clone https://github.com/yourusername/RayPulse.git
    cd RayPulse
    ```

2. **Build with Meson:**
    ```bash
    meson setup build
    meson compile -C build
    ```

    Or use the provided Makefile:
    ```bash
    make build
    ```

---

## 🚀 Usage

- **Run the Ray Tracer:**
    ```bash
    ./build/ray_pulse > image.ppm
    ```
    This will render an image and save it as `image.ppm`.

- **View the Output:**
    Open `image.ppm` with an image viewer that supports PPM format, or convert it to PNG/JPG using tools like ImageMagick:
    ```bash
    convert image.ppm image.png
    ```

---

## 📂 Structure

```
RayPulse/
├── include/                # C++ headers (vec3, ray, color, hittable, sphere, etc.)
├── src/
│   ├── main.cpp            # Program entry point (renders a simple scene)
│   └── shaders/            # OpenGL shaders (vertex_shader.glsl, fragment_shader.glsl)
├── build/                  # Meson build directory (created after build)
├── Makefile                # Convenience build/run targets
├── meson.build             # Meson build configuration
├── README.md
└── LICENSE
```

---

## 🔮 Future Enhancements

- **Physically-Based Materials**: Extend the renderer to handle metals, dielectrics, and more complex BRDFs.  
- **Motion & Animation**: Support moving objects and animated scenes for video output.  
- **Relativistic Effects**: Simulate gravitational lensing and black holes for advanced CGM visualizations.  
- **Real-Time Rendering**: Integrate OpenGL or Vulkan to display progressive raytraced images in a window.  
- **GPU Acceleration**: Port rendering kernels to CUDA or compute shaders for faster frame generation.  
- **Multithreading & Performance**: Utilize all CPU cores efficiently for faster renders.  
- **Scene Complexity**: Add more shapes, textures, volumetric effects, and lights.  
- **Anti-Aliasing & Denoising**: Improve image quality with supersampling and post-processing filters.  
- **User Controls & Interactivity**: Allow camera movement, scene editing, and parameter tweaking in real time.


---

## 📜 License

This project is open-source and available under the [MIT License](LICENSE).
