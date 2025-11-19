project(
    'raypulse',
    ['c', 'cpp'],
    meson_version : '>= 1.3.0',
    version : '0.1',
    default_options : [
        'warning_level=3'
    ],
)

c_compiler = meson.get_compiler('c')

if c_compiler.get_id() == 'clang-cl'
    add_project_arguments('-Wno-c23-extensions', language : 'c')
endif

lib_include_dir = include_directories('../libraries/include')
prj_include_dir = include_directories('include')

imgui_src_dir = 'src/imgui'
imgui_include_dir = include_directories(imgui_src_dir)

imgui_sources = [
    join_paths(imgui_src_dir, 'imgui.cpp'),
    join_paths(imgui_src_dir, 'imgui_draw.cpp'),
    join_paths(imgui_src_dir, 'imgui_widgets.cpp'),
    join_paths(imgui_src_dir, 'imgui_tables.cpp'),
    join_paths(imgui_src_dir, 'backends/imgui_impl_glfw.cpp'),
    join_paths(imgui_src_dir, 'backends/imgui_impl_opengl3.cpp'),
]

glad_src = '../libraries/src/glad.c'
glfw_lib = '../libraries/lib/glfw3.lib'
glm_lib = '../libraries/lib/glm.lib'

glm_include_dir = include_directories('../libraries/include/glm')
imath_include_dir = include_directories('../libraries/include/Imath')

lib_dir = meson.current_source_dir() / '../libraries/lib'

glad_dep = declare_dependency(
    sources : files(glad_src),
    include_directories : lib_include_dir
)

glfw_dep = declare_dependency(
    dependencies : [meson.get_compiler('c').find_library('glfw3_mt', dirs : lib_dir)],
    include_directories : lib_include_dir
)

glm_dep = declare_dependency(
    dependencies : [meson.get_compiler('cpp').find_library('glm', dirs : lib_dir)],
    include_directories : glm_include_dir
)

openexr_libs = [
    'OpenEXR-3_4',
    'OpenEXRCore-3_4',
    'OpenEXRUtil-3_4',
    'Iex-3_4',
    'IlmThread-3_4',
    'Imath-3_2',       # Core math library
    'openjph.0.24',    # JPEG 2000 compression
]

openexr_dep_list = []
foreach lib_name : openexr_libs
    openexr_dep_list += meson.get_compiler('cpp').find_library(lib_name, dirs : lib_dir)
endforeach

openexr_dep = declare_dependency(
    dependencies : openexr_dep_list,
    include_directories : lib_include_dir
)

# Define the list of DLLs base names
openexr_dlls = [
    'OpenEXR-3_4.dll',
    'OpenEXRCore-3_4.dll',
    'Iex-3_4.dll',
    'IlmThread-3_4.dll',
    'Imath-3_2.dll',
    'openjph.0.24.dll',
]

# --- DLL COPY SETUP ---

# 1. Source files for install_data (DLLs are physically located in ../libraries/lib/)
full_dll_paths = []
foreach dll_name : openexr_dlls
    full_dll_paths += '..//libraries/lib/' + dll_name
endforeach

# 2. Add glfw3.dll to the list of DLLs that need copying
all_runtime_dlls = openexr_dlls + ['glfw3.dll']

# 3. Define the directory paths for the custom target
powershell_cmd = find_program('powershell')
# Source: points to the 'lib' folder where all DLLs are now located
dll_source_dir = '../../libraries/lib/*'
# Destination: the build root (where the executable is)
dll_target_dir = './'


# Install the DLLs during the install step
install_data(
    sources: files(full_dll_paths),
    install_dir: get_option('bindir'),
    install_mode: 'rwxr-xr-x'
)


# For running *during* development (the actual runtime fix)
custom_target('copy_runtime_dlls',
              # Input list is used for dependency tracking
              input: files(full_dll_paths, '../libraries/lib/glfw3.dll'),

              # Output is the list of ALL base DLL names
              output: all_runtime_dlls,

              # FIX: Use Copy-Item with explicit path variables
              command: [powershell_cmd,
                        '-Command',
                        'Copy-Item',
                        '-Path', dll_source_dir,
                        '-Destination', dll_target_dir,
                        '-Include', '*.dll',
                        '-Recurse',
                        '-Force'
              ],
              build_by_default: true
)


dependencies = [
    glad_dep,
    glfw_dep,
    glm_dep,
    openexr_dep,
    dependency('opengl')
]


executable(
    'main',
    ['src/main.cpp','src/texture.cpp', 'src/shader.cpp', 'src/renderer.cpp', 'src/export.cpp'] + imgui_sources,
    dependencies : dependencies,
    include_directories : [lib_include_dir, prj_include_dir, glm_include_dir, imath_include_dir, imgui_include_dir],
    install : true
)