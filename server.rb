require 'sinatra'
require 'rack-flash'
require 'omniauth'
require 'omniauth-identity'
require 'json'
require 'sequel'
require 'sqlite3'
require 'bunny'
require 'haml'
require 'shellwords'
require 'tempfile'
require 'securerandom'
require 'digest/md5'
require_relative 'db'
require_relative 'submission_rankings'
require_relative 'message_queue'
require_relative 'task_submission'

def get_or_post(*args, &block)
  get(*args, &block)
  post(*args, &block)
end

Sequel::Model.db = Sequel.sqlite('db.sqlite')
AMQPManager.start  unless ENV["UNICORN"]

set :bind, '0.0.0.0'
set :port, 4567

# ToDo: we should think about https (to prevent cookies stealing)
# ToDo: secret key should be set in env (but for demo version we leave it unsafe)
use Rack::Session::Cookie, {:key => 'rack.session',
                            :path => '/',
                            :expire_after => 30*24*3600, # In seconds
                            :secret => 'SomeSecretKeyToBeChanged',
                            :old_secret => 'SomeSecretKeyToAllowSecretRotation',
                          }
use Rack::Flash, :accessorize => [:notice, :error]

use OmniAuth::Builder do
  provider  :identity,
            fields: [:email, :name],
            model: User,
            on_registration:        ->(env){ call env.merge('PATH_INFO' => '/sign_up') },
            on_failed_registration: ->(env){ call env.merge('PATH_INFO' => '/sign_up') }
            # (alternative)         ->(env){ Rack::Response.new{|resp| resp.redirect("/sign_up") }.finish }
end
set :layout_engine, :haml

helpers do
  def current_user
    @current_user ||= User.first(id: session[:user_id])  if session[:user_id]
  end
  def signed_in?
    !!current_user
  end
end

def authenticated(&block)
  if signed_in?
    yield
  else
    flash[:error] = 'You should be authenticated to proceed'
    redirect '/'
  end
end

get '/sign_up' do
  haml :registration_form
end

get '/' do
  haml :index
end

get_or_post '/auth/identity/callback' do
  auth = request.env['omniauth.auth']
  session[:user_id] = auth['uid']
  redirect '/'
end

post '/auth/logout' do
  session[:user_id] = nil
  redirect '/'
end

get '/auth/failure' do
  flash[:error] = 'Invalid credentials'
  redirect '/'
end


post '/submit_batch' do
  authenticated do
    unless submission_name = params[:submission_name]
      flash[:error] = 'Specify a descriptive name for your submission'
      redirect('/submit_batch') and return
    end

    unless submissions_archive_file = params[:submissions_archive_file]
      flash[:error] = 'You should supply at least one file'
      redirect('/submit_batch') and return
    end

    submissions_archive_file.each do |file_cfg|
      process_single_submitted_file(file_cfg, submission_name, current_user)
    end
    redirect '/personal_submissions'
  end
end

post '/submit' do
  authenticated do
    submission_variant = params[:submission_variant]
    unless SUBMISSION_VARIANTS.has_key?(submission_variant)
      flash[:error] = "Unknown submission variant `#{submission_variant}`"
      redirect('/') and return
    end

    submission_type = SUBMISSION_VARIANTS[submission_variant][:submission_type]
    case submission_type
    when 'motif'
      config = motif_submission_config(params)
      if !(params[:motif_file] || params[:motif] && !params[:motif].empty?)
        flash[:error] = "Upload a file with predictions"
        redirect '/submit_motif'
      end
    when 'predictions'
      if !params[:predictions_file]
        flash[:error] = "Upload a file with predictions"
        redirect '/submit_predictions'
      end
      config = motif_predictions_config(params)
    else
      flash[:error] = "Unknown submission type"
      redirect '/'
    end

    submission_name = params[:submission_name]&.strip
    unless submission_name && !submission_name.empty?
      flash[:error] = 'Specify a descriptive name for your submission'
      redirect("/submit_#{submission_type}") and return
    end
    submit_task(config, submission_name, current_user)
    redirect "/submissions/#{submission_variant}"
  end
end

get '/submit_motif' do
  haml :submit_motif, locals: {submission_variants: submission_variants_by_type('motif')}
end
get '/submit_predictions' do
  haml :submit_predictions, locals: {submission_variants: submission_variants_by_type('predictions')}
end
get '/submit_batch' do
  haml :submit_batch
end

get '/submission_variants' do
  haml :submission_variants
end


get '/submissions/:submission_variant' do
  submission_variant = params[:submission_variant]
  submission_type = SUBMISSION_VARIANTS[submission_variant][:submission_type]
  submissions = Submission.where(submission_variant: submission_variant).all
  ranks = with_total_ranks(submission_ranks(submissions))

  if params[:personal]
    submissions = submissions.select{|submission|
      submission.user_id == current_user.id
    }
  end

  is_recent = false
  if params[:recent] && params[:recent] != 'false'
    is_recent = true
    submissions = most_recent_submissions(submissions, submissions_per_user: 1)
  end

  submissions = submissions.sort_by(&:submission_time).reverse
  benchmarks = benchmarks_by_type(submission_type).sort_by{|bm| bm[:name] }
  haml :submissions, locals: {submissions: submissions, benchmarks: benchmarks, ranks: ranks, is_recent: is_recent}
end

get '/personal_submissions' do
  user_submissions = Submission.where(user_id: current_user.id).all

  is_recent = false
  if params[:recent] && params[:recent] != 'false'
    is_recent = true
    user_submissions = most_recent_submissions(user_submissions, submissions_per_user: 1)
  end

  user_submissions = user_submissions.sort_by(&:submission_time).reverse
  submission_ranks = user_submissions.map{|user_submission|
    all_submissions = Submission.where(submission_variant: user_submission.submission_variant).all

    # we measure rank in case that this user's submission was the last and other playeers ranks are the same
    most_recent = most_recent_submissions(all_submissions)
    most_recent_user_submission = most_recent.detect{|submission| submission.user_id == current_user.id }
    other_user_submissions = most_recent.reject{|submission| submission.user_id == current_user.id }
    concurring_submissions = other_user_submissions + [user_submission, most_recent_user_submission].compact.uniq
    ranks = with_total_ranks(submission_ranks(concurring_submissions))
    [user_submission, ranks[user_submission][:total_rank]]
  }.to_h
  haml :personal_submissions, locals: {submissions: user_submissions, is_recent: is_recent, submission_ranks: submission_ranks}
end

get '/mixed_submissions' do
  submissions = Submission.all

  is_recent = false
  if params[:recent] && params[:recent] != 'false'
    is_recent = true
    submissions = most_recent_submissions(submissions, submissions_per_user: 1)
  end

  submissions = submissions.sort_by(&:submission_time).reverse
  haml :personal_submissions, locals: {submissions: submissions, is_recent: is_recent}
end

get '/leaderboard' do
  haml :leaderboard
end


get '/docs' do
  haml :docs_general
end

get '/tech-docs' do
  haml :docs_technical
end

get '/random_submission_name' do
  # Here should be some random phrases
  {name: SecureRandom.alphanumeric(10)}.to_json
end
