project('RayPulse', 'c',
  version : '0.1',
  default_options : ['c_std=c99']
)

src = files('src/main.c', 'src/utils/read_file.c')
inc = include_directories('include')

glfw_dep = dependency('glfw3', required : true)
glew_dep = dependency('glew', required : true)
opengl_dep = dependency('opengl', required : true)

executable('ray_pulse', src,
  include_directories : inc,
  dependencies : [glfw_dep, glew_dep, opengl_dep],
  install : true
)