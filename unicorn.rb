require 'mongoid'
require 'message_queue'

before_fork do |server, worker|
  Mongoid.clients.each do |name, client|
    client.close
  end
end

after_fork do |server, worker|
  Mongoid.clients.each do |name, client|
    # client.close
    client.reconnect
  end
  AMQPManager.start
end
