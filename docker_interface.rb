require 'shellwords'

def docker_mount_option(src:, dst:, readonly: false)
  "--mount type=bind,dst=#{dst.shellescape},src=#{src.shellescape}" + (readonly ? ',readonly' : '')
end

def run_docker(docker_image:, mounts:, additional_options: '', args: '')
  mount_options = mounts.map{|opts| docker_mount_option(**opts) }.join(' ')
  cmd = "docker run --rm #{mount_options} #{additional_options} #{docker_image} #{args}"
  $stderr.puts cmd
  system(cmd)
end

def run_benchmark_docker(docker_image:, common_data_folder:, benchmark_specific_data_folder:, scene_folder:, benchmark_folder:)
  config_fn = File.join(scene_folder, 'config.json')
  mounts = [
    {dst: '/common_data', src: common_data_folder, readonly: true},
    {dst: '/benchmark_specific_data', src: benchmark_specific_data_folder, readonly: true},
    {dst: '/workdir/config.json', src: config_fn, readonly: true},
    {dst: '/workdir/persistent', src: benchmark_folder},
  ]
  run_docker(docker_image: docker_image, mounts: mounts)
end

def run_preprocess_docker(docker_image:, common_data_folder:, common_data_readonly: true, benchmark_specific_data_folder:)
  mounts = [
    {dst: '/common_data', src: common_data_folder, readonly: common_data_readonly},
    {dst: '/benchmark_specific_data', src: benchmark_specific_data_folder},
  ]
  run_docker(docker_image: docker_image, mounts: mounts, additional_options: '--entrypoint /app/preprocess')
end
