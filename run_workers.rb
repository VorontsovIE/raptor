require 'bunny'
require 'sequel'
require 'json'
require 'shellwords'
require 'fileutils'
require_relative 'db'
require_relative 'message_queue'

def docker_mount_option(src:, dst:, readonly: false)
  "--mount type=bind,dst=#{dst.shellescape},src=#{src.shellescape}" + (readonly ? ',readonly' : '')
end

def run_docker(docker_image:, data_folder:, scene_folder:, benchmark_folder:)
  config_fn = File.join(scene_folder, 'config.json')
  mounts = [
    {dst: '/data', src: data_folder, readonly: true},
    {dst: '/workdir/config.json', src: config_fn, readonly: true},
    {dst: '/workdir/persistent', src: benchmark_folder},
  ]
  mount_options = mounts.map{|opts| docker_mount_option(**opts) }.join(' ')
  cmd = "docker run --rm #{mount_options} #{docker_image}"
  system(cmd)
end

def store_metrics_to_db(benchmark_folder, benchmark_run)
  result_fn = File.join(benchmark_folder, 'result.json')
  results = JSON.parse(File.read(result_fn))
  results['metrics'].each{|measure_type_name, value|
    benchmark_run.add_score_for_measure(measure_type_name, value)
  }
end

def process_submission(submission, benchmark_config)
  benchmark_name = benchmark_config['benchmark_name']
  benchmark = Benchmark.first(name: benchmark_name)
  time = Time.now
  benchmark_run = submission.add_benchmark_run(benchmark_id: benchmark.id, status: 'started', creation_time: time, modification_time: time)

  scene_folder = File.join(SCENE_PATH, submission.ticket)
  benchmark_folder = File.join(scene_folder, benchmark_name)
  FileUtils.mkdir_p(benchmark_folder)
  success = run_docker({
    docker_image: benchmark_config['docker_image'],
    data_folder: File.join(DATA_PATH, submission.species, submission.tf),
    scene_folder: scene_folder,
    benchmark_folder: benchmark_folder,
  })
  if success
    store_metrics_to_db(benchmark_folder, benchmark_run)
    benchmark_run.update(status: 'finished', modification_time: Time.now)
  else
    benchmark_run.update(status: 'failed', modification_time: Time.now)
  end
end

AMQPManager.start
AMQPManager.channel.prefetch(1)

DATA_PATH = File.absolute_path('data', __dir__)
SCENE_PATH = File.absolute_path('scene', __dir__)
FileUtils.mkdir_p SCENE_PATH

benchmark_configs = JSON.parse(File.read('benchmark_configs.json'))
begin
  benchmark_configs.each do |benchmark_config|
    queue = AMQPManager.channel.queue(benchmark_config['benchmark_name'], no_declare: true)
    queue.subscribe(manual_ack: true) do |delivery_info, _properties, body|
      scheduled_task = JSON.parse(body)
      ticket = scheduled_task['ticket']
      submission = Submission.first(ticket: ticket)
      process_submission(submission, benchmark_config)
      AMQPManager.channel.ack(delivery_info.delivery_tag)
    end
  end
  loop{ sleep 5 }
rescue Interrupt => _
  AMQPManager.stop
  exit(0)
end
