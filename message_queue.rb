require 'bunny'

module AMQPManager
  def self.connection; @connection; end
  def self.channel; @channel; end

  def self.start
    @connection = Bunny.new
    @connection.start
    @channel = @connection.create_channel
    @channel.confirm_select
  end
  def self.stop
    @connection.close
  end

  def self.get_exchange(exchange_name)
    @exchanges ||= {}
    @exchanges[exchange_name] ||= @channel.fanout(exchange_name, durable: true)
  end

  def self.schedule_task(ticket:, exchange:)
    msg = {ticket: ticket}.to_json
    get_exchange(exchange).publish(msg, persistent: true)
    @channel.wait_for_confirms
  end
end
