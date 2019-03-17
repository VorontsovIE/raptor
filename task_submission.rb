require 'digest/md5'
require_relative 'db'
require_relative 'message_queue'

def submit_task(config, submission_name, current_user)
  if submission = duplicate_submission(config)
    submission.update(submission_time: Time.now, name: submission_name)
    return
  end

  if Submission.first(user_id: current_user.id, submission_variant: config[:submission_variant], name: submission_name)
    raise 'Submission with that exact name but different content already exists'
  end

  ticket = SecureRandom.alphanumeric(10)
  FileUtils.mkdir_p "scene/#{ticket}"
  File.write("scene/#{ticket}/config.json", config.to_json)

  now = Time.now
  submission = Submission.create({
    user_id: current_user.id,
    name: submission_name,
    ticket: ticket,
    config_hash: Digest::MD5.hexdigest(config.to_json),
    submission_variant: config[:submission_variant],
    creation_time: now,
    submission_time: now,
  })
  raise 'Submission not created'  if !submission
  AMQPManager.schedule_task(ticket: ticket, exchange: submission.submission_type)
end


def schedule_submission_file(submission_variant, content, submission_name, current_user)
  config = config_by_submission_content(submission_variant, content)
  submit_task(config, submission_name, current_user)
end

# `file_cfg` is a properties hash for a submitted file Tempfile object (which is given by rack)
def process_single_submitted_file(file_cfg, submission_name, current_user)
  filename = File.basename(file_cfg[:filename])
  if filename.end_with?('.tar.gz')
    tmp_folder = File.join(Dir.tmpdir, SecureRandom.alphanumeric(10))
    begin
      FileUtils.mkdir_p(tmp_folder)
      system("tar -zx -C #{tmp_folder.shellescape} -f #{file_cfg[:tempfile].path.shellescape}")
      Dir.children(tmp_folder).each do |single_fn|
        submission_variant = File.basename(single_fn, File.extname(single_fn))
        content = File.read(File.join(tmp_folder, single_fn))
        schedule_submission_file(submission_variant, content, submission_name, current_user)
      end
    ensure
      FileUtils.rm_r(tmp_folder)
    end
  else
    submission_variant = File.basename(filename, File.extname(filename))
    content = file_cfg[:tempfile].read
    schedule_submission_file(submission_variant, content, submission_name, current_user)
  end
end

def config_by_submission_file(submission_file, filename: nil)
  filename ||= submission_file.path
  submission_variant = File.basename(filename, File.extname(filename))
  content = File.read(submission_file)
  config_by_submission_content(submission_variant, content)
end

def config_by_submission_content(submission_variant, content)
  raise "Wrong submission variant `#{submission_variant}`"  unless SUBMISSION_VARIANTS.has_key?(submission_variant)
  sv_config = SUBMISSION_VARIANTS[submission_variant]
  config = parse_submission_content(submission_variant, content)
  config.merge({
    tf: sv_config[:tf],
    species: sv_config[:species],
    submission_variant: submission_variant,
  })
end


def parse_submission_content(submission_variant, content)
  raise "Unknown submission variant `#{submission_variant}`"  unless SUBMISSION_VARIANTS.has_key?(submission_variant)
  sv_config = SUBMISSION_VARIANTS[submission_variant]
  submission_type = sv_config[:submission_type]
  case submission_type
  when 'motif'
    {
      # motif: content.lines.map{|l| l.chomp.split.map(&:to_f) }
      motif: content
    }
  when 'predictions'
    {
      predictions: content.lines.map(&:strip).map(&:to_f)
    }
  else
    raise "Unknown submission type `#{submission_type}`"
  end
end

def motif_submission_config(params)
  if params[:motif_file]
    content = params[:motif_file][:tempfile].read
  else
    content = params[:motif]
  end
  config_by_submission_content(params[:submission_variant], content)
end

def motif_predictions_config(params)
  content = params[:predictions_file][:tempfile].read
  config_by_submission_content(params[:submission_variant], content)
end

def duplicate_submission(config)
  config_hash = Digest::MD5.hexdigest(config.to_json)
  Submission.first(user_id: current_user.id, submission_variant: config[:submission_variant], config_hash: config_hash)
end
