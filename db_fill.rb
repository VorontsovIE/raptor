require 'sequel'
require 'sqlite3'
require_relative 'db'
require_relative 'message_queue'

DB = Sequel.sqlite('db.sqlite')
Sequel::Model.db = DB

# Create AMQP queues
AMQPManager.start
SUBMISSION_TYPES.each do |submission_type|
  exchange_name = submission_type
  exchange = AMQPManager.get_exchange(exchange_name)
  benchmarks_by_type(submission_type).each do |benchmark_name, benchmark_config|
    queue_name = benchmark_name
    AMQPManager.channel.queue(queue_name, durable: true).bind(exchange)
  end
end
