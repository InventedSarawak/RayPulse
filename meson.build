project(
    'raypulse',
    ['c', 'cpp'],
    meson_version : '>= 1.3.0',
    version : '0.1',
    default_options : ['warning_level=3'],
)

c_compiler = meson.get_compiler('c')
cpp_compiler = meson.get_compiler('cpp')

if c_compiler.get_id() == 'clang-cl'
    add_project_arguments('-Wno-c23-extensions', language : 'c')
endif

prj_include_dir = include_directories('include')
glad_include_dir = include_directories('external/glad/include')
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

glad_src = 'external/glad/src/gl.c'

glad_dep = declare_dependency(
    sources : files(glad_src),
    include_directories : glad_include_dir
)

glfw_dep = dependency('glfw3', required: true)
opengl_dep = dependency('opengl', required: true)

openexr_dep = dependency('OpenEXR', required: false)
if not openexr_dep.found()
    openexr_libs = ['IlmImf-2_5', 'Imath-2_5', 'Half-2_5', 'Iex-2_5', 'IexMath-2_5', 'IlmThread-2_5']
    openexr_dep_list = []
    foreach lib_name : openexr_libs
        openexr_dep_list += cpp_compiler.find_library(lib_name, required: true)
    endforeach
    openexr_dep = declare_dependency(dependencies : openexr_dep_list)
endif

# Compute shader compilation
glslc = find_program('glslangValidator', required : false)

if glslc.found()
    compute_shader_spv = custom_target('compile_compute_shader',
        input : 'shaders/compute/main.glsl',
        output : 'main.spv',
        command : [glslc, '-G', '-S', 'comp', '-Ishaders/compute', '@INPUT@', '-o', '@OUTPUT@'],
        build_always_stale : true,
        install : true,
        install_dir : get_option('bindir')
    )
    shader_deps = [compute_shader_spv]
else
    warning('glslangValidator not found, compute shader will not be compiled')
    shader_deps = []
endif

dependencies = [glad_dep, glfw_dep, opengl_dep, openexr_dep]

executable(
    'raypulse',
    ['src/main.cpp', 'src/texture.cpp', 'src/shader.cpp', 'src/renderer.cpp', 'src/export.cpp'] + imgui_sources,
    dependencies : dependencies,
    include_directories : [prj_include_dir, glad_include_dir, imgui_include_dir],
    link_depends : shader_deps,
    install : true
)
