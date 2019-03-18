require_relative 'message_queue'
raise 'Specify ticket' unless ticket = ARGV[0]
raise 'Specify submission type (motif/predictions)' unless submission_type = ARGV[1]
AMQPManager.start
AMQPManager.schedule_task(ticket: ticket, exchange: submission_type)
