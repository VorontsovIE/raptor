require 'json'
require 'sequel'
require 'sqlite3'
require_relative 'db'
require_relative 'message_queue'

DB = Sequel.sqlite('db.sqlite')
Sequel::Model.db = DB

benchmark_configs = JSON.parse(File.read('benchmark_configs.json'))
benchmark_configs.each do |config|
  benchmark = Benchmark.find_or_create({
    name: config['benchmark_name'],
    submission_type: config['submission_type'],
    docker_image: config['docker_image'],
  })

  config['metrics'].each do |metric_config|
    MeasureType.find_or_create({
      benchmark_id: benchmark.id,
      name: metric_config['metric_name'],
      greater_is_better: metric_config['greater_is_better'],
    })
  end
end

submission_variant_configs = JSON.parse(File.read('submission_variants.json'))
submission_variant_configs.each do |config|
  SubmissionVariant.find_or_create({
    species: config['species'],
    tf: config['tf'],
    name: config['name'],
    submission_type: config['submission_type'],
  })
end

# Create AMQP queues
AMQPManager.start
benchmark_configs.group_by{|config|
  config['submission_type']
}.each do |submission_type, configs|
  exchange_name = submission_type
  exchange = AMQPManager.get_exchange(exchange_name)
  configs.each do |config|
    queue_name = config['benchmark_name']
    AMQPManager.channel.queue(queue_name, durable: true).bind(exchange)
  end
end
