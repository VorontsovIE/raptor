require 'sinatra'
require 'rack-flash'
require 'omniauth'
require 'omniauth-identity'
require 'json'
require 'sequel'
require 'sqlite3'
require 'bunny'
require 'haml'
require 'securerandom'
require_relative 'db'
require_relative 'submission_rankings'
require_relative 'message_queue'

def motif_submission_config(params)
  submission_type = params[:submission_type]
  submission_variant = params[:submission_variant]
  submission_variant_config = SUBMISSION_VARIANTS[submission_variant]
  if params[:motif_file]
    motif = params[:motif_file][:tempfile].read
  else
    motif = params[:motif]
  end
  tf      = submission_variant_config[:tf]
  species = submission_variant_config[:species]

  {motif: motif, tf: tf, species: species, submission_type: submission_type, submission_variant: submission_variant}
end

def motif_predictions_config(params)
  submission_type = params[:submission_type]
  submission_variant = params[:submission_variant]
  submission_variant_config = SUBMISSION_VARIANTS[submission_variant]
  unparsed_predictions = params[:predictions_file][:tempfile].read
  predictions = unparsed_predictions.lines.map(&:strip).map(&:to_f)
  tf      = submission_variant_config[:tf]
  species = submission_variant_config[:species]

  {predictions: predictions, tf: tf, species: species, submission_type: submission_type, submission_variant: submission_variant}
end

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

post '/submit' do
  authenticated do
    submission_type = params[:submission_type]
    submission_variant = params[:submission_variant]
    case submission_type
    when 'motif'
      config = motif_submission_config(params)
    when 'predictions'
      config = motif_predictions_config(params)
    else
      flash[:error] = "Unknown submission type"
      redirect '/'
    end

    ticket = SecureRandom.alphanumeric(10)
    FileUtils.mkdir_p "scene/#{ticket}"
    File.write("scene/#{ticket}/config.json", config.to_json)

    current_user.send_submission(ticket: ticket, submission_type: submission_type, submission_variant: submission_variant)
    AMQPManager.schedule_task(ticket: ticket, exchange: submission_type)
    flash[:notice] = "Your submission got id <strong>#{ticket}</strong>."
    redirect "/submissions/#{submission_variant}"
  end
end

get '/submit_motif' do
  haml :submit_motif, locals: {submission_variants: submission_variants_by_type('motif')}
end
get '/submit_predictions' do
  haml :submit_predictions, locals: {submission_variants: submission_variants_by_type('predictions')}
end

get '/submissions/:submission_variant' do
  submissions = Submission.where(submission_variant: params[:submission_variant]).all
  ranks = with_total_ranks(submission_ranks(submissions))

  if params[:personal]
    submissions = submissions.select{|submission|
      submission.user_id == current_user.id
    }
  end

  is_recent = false
  if params[:recent] && params[:recent] != 'false'
    is_recent = true
    submissions = submissions.group_by{|submission|
      [submission.user_id, submission.submission_variant]
    }.map{|uid_variant_pair, submissions_group|
      submissions_group.max_by(&:creation_time)
    }
  end

  # if params[:leaders]
  #   submissions = submissions.group_by{|submission|
  #     submission.submission_variant
  #   }.flat_map{|variant, submissions_group|
  #     # rankings(submissions_group)
  #     best_ranked(submissions_group)
  #   }
  # end

  submissions = submissions.sort_by(&:creation_time).reverse
  benchmarks = benchmarks_by_type('motif').sort_by{|bm| bm[:name] }
  haml :submissions, locals: {submissions: submissions, benchmarks: benchmarks, ranks: ranks, is_recent: is_recent}
end

get '/submissions/predictions' do
  submissions = Submission.where({
    submission_type: 'predictions', user_id: current_user.id
  }).all.sort_by(&:creation_time).reverse
  benchmarks = benchmarks_by_type('predictions').sort_by{|bm| bm[:name] }
  haml :submissions, locals: {submissions: submissions, benchmarks: benchmarks}
end

get '/leaderboard/motif' do
  best_submissions = submission_variants_by_type('motif').each_key.flat_map{|submission_variant|
    variant_submissions = Submission.where(submission_variant: submission_variant).to_a
    best_submissions(variant_submissions)
  }
  benchmarks = benchmarks_by_type('motif').sort_by{|bm| bm[:name] }
  haml :submissions, locals: {submissions: best_submissions, benchmarks: benchmarks}
end


get '/docs' do
  haml :docs_general
end

get '/tech-docs' do
  haml :docs_technical
end
