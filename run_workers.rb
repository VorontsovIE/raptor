require 'bunny'
require 'sequel'
require 'json'
require 'shellwords'
require 'fileutils'
require_relative 'db'
require_relative 'message_queue'
require_relative 'docker_interface'

def store_metrics_to_db(benchmark_folder, benchmark_run)
  result_fn = File.join(benchmark_folder, 'result.json')
  results = JSON.parse(File.read(result_fn))
  results['metrics'].each{|measure_type_name, value|
    benchmark_run.add_score_for_measure(measure_type_name, value)
  }
end

def process_submission(submission, benchmark_name, benchmark_config)
  time = Time.now
  benchmark_run = submission.add_benchmark_run(benchmark_name: benchmark_name, status: 'started', creation_time: time, modification_time: time)

  scene_folder = File.join(SCENE_PATH, submission.ticket)
  benchmark_folder = File.join(scene_folder, benchmark_name)
  FileUtils.mkdir_p(benchmark_folder)
  success = run_benchmark_docker({
    docker_image: benchmark_config[:docker_image],
    common_data_folder: File.join(DATA_PATH, submission.species, submission.tf),
    benchmark_specific_data_folder: File.join(DATA_PATH, submission.species, submission.tf, benchmark_name),
    scene_folder: scene_folder,
    benchmark_folder: benchmark_folder,
  })
  if success
    store_metrics_to_db(benchmark_folder, benchmark_run)
    benchmark_run.update(status: 'finished', modification_time: Time.now)
  else
    benchmark_run.update(status: 'failed', modification_time: Time.now)
  end
  success
end

AMQPManager.start
AMQPManager.channel.prefetch(1)

DATA_PATH = File.absolute_path('data', __dir__)
SCENE_PATH = File.absolute_path('scene', __dir__)
FileUtils.mkdir_p SCENE_PATH

begin
  SUBMISSION_TYPES.each do |submission_type|
    benchmarks_by_type(submission_type).each do |benchmark_name, benchmark_config|
      queue = AMQPManager.channel.queue(benchmark_name, no_declare: true)
      queue.subscribe(manual_ack: true) do |delivery_info, _properties, body|
        scheduled_task = JSON.parse(body)
        ticket = scheduled_task['ticket']
        puts "Started processing of #{ticket}."
        if submission = Submission.first(ticket: ticket)
          success = process_submission(submission, benchmark_name, benchmark_config)
        else
          puts "No submission for #{ticket} in database"
          success = false
        end
        puts "Completion status of #{ticket}: `#{success ? "ok" : "fail"}`."
        AMQPManager.channel.ack(delivery_info.delivery_tag)
      end
    end
  end
  loop{ sleep 5 }
rescue Interrupt => _
  AMQPManager.stop
  exit(0)
end
