project(
    'raypulse',
    ['c', 'cpp'],
    meson_version : '>= 1.3.0',
    version : '0.1',
    default_options : [
        'warning_level=3',
        'cpp_std=c++latest',
    ],
)

c_compiler = meson.get_compiler('c')
cpp_compiler = meson.get_compiler('cpp')

if c_compiler.get_id() == 'clang-cl'
    add_project_arguments('-Wno-c23-extensions', language : 'c')
endif

if cpp_compiler.get_id() == 'clang-cl' or cpp_compiler.get_id() == 'msvc'
    add_project_arguments('/std:c++latest', language : 'cpp')
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
    'Imath-3_2', # Core math library
    'openjph.0.24', # JPEG 2000 compression
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

full_dll_paths = []
foreach dll_name : openexr_dlls
    full_dll_paths += '..//libraries/lib/' + dll_name
endforeach

all_runtime_dlls = openexr_dlls + ['glfw3.dll']

powershell_cmd = find_program('powershell')
dll_source_dir = '../../libraries/lib/*'
dll_target_dir = './'


install_data(
    sources : files(full_dll_paths),
    install_dir : get_option('bindir'),
    install_mode : 'rwxr-xr-x'
)


copy_runtime_dlls = custom_target('copy_runtime_dlls',
                                  input : files(full_dll_paths, '../libraries/lib/glfw3.dll'),

                                  output : all_runtime_dlls,
                                  build_always_stale : true,

                                  command : [powershell_cmd,
                                             '-Command',
                                             'Copy-Item',
                                             '-Path', dll_source_dir,
                                             '-Destination', dll_target_dir,
                                             '-Include', '*.dll',
                                             '-Recurse',
                                             '-Force'
                                  ]
)

glslc = find_program('glslc', required : true)

compute_shader_spv = custom_target('compile_compute_shader',
                                   input : 'shaders/compute/main.glsl',
                                   output : 'main.spv',
                                   command : [
                                       glslc,
                                       '-fshader-stage=compute',
                                       '--target-env=opengl',
                                       '-fauto-map-locations',
                                       '-g',
                                       '@INPUT@',
                                       '-o', '@OUTPUT@'
                                   ],
                                   build_always_stale : true,
                                   install : true,
                                   install_dir : get_option('bindir') # Install next to the executable
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
    [
        'src/main.cpp',
        'src/texture.cpp',
        'src/shader.cpp',
        'src/renderer.cpp',
        'src/export.cpp',
        'src/SceneLoader.cpp',
        'src/MaterialFactory.cpp',
        'src/SceneBuilder.cpp'
    ] + imgui_sources,
    dependencies : dependencies,
    include_directories : [lib_include_dir, prj_include_dir, glm_include_dir, imath_include_dir, imgui_include_dir],
    link_depends : [compute_shader_spv, copy_runtime_dlls],
    install : true
)

executable(
    'test1',
    ['test.cpp', 'src/texture.cpp', 'src/shader.cpp', 'src/renderer.cpp', 'src/export.cpp'],
    dependencies : dependencies,
    include_directories : [lib_include_dir, prj_include_dir, glm_include_dir, imath_include_dir, imgui_include_dir],
    install : true
)