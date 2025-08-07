project('RayPulse', 'c',
  version : '0.1',
  default_options : ['c_std=c99']
)

src = files('src/main.c')

glfw_dep = dependency('glfw3', required : true)
glew_dep = dependency('glew', required : true)
opengl_dep = dependency('opengl', required : true)
# m_dep = dependency('m', required : false)

executable('ray_pulse', src,
  dependencies : [glfw_dep, glew_dep, opengl_dep],
  install : true
)