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
require_relative 'message_queue'

def motif_submission_config(params)
  submission_type = params[:submission_type]
  submission_variant_config = JSON.parse(params[:submission_variant])
  motif = params[:motif]
  tf      = submission_variant_config['tf']
  species = submission_variant_config['species']

  {motif: motif, tf: tf, species: species, submission_type: submission_type}
end

def motif_predictions_config(params)
  submission_type = params[:submission_type]
  submission_variant_config = JSON.parse(params[:submission_variant])
  predictions = params[:predictions].lines.map(&:strip).map(&:to_f)
  tf      = submission_variant_config['tf']
  species = submission_variant_config['species']

  {predictions: predictions, tf: tf, species: species, submission_type: submission_type}
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
  provider :developer
  provider :identity, :fields => [:email, :name], model: User #, on_login: ->(env){ render 'sign_in' }
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
    case submission_type
    when 'motif'
      config = motif_submission_config(params)
    when 'predictions'
      config = motif_predictions_config(params)
    else
      flash[:error] = "Unknown submission type"
      redirect '/'
    end
    
    submission_variant = SubmissionVariant.first(submission_type: submission_type, tf: config[:tf], species: config[:species])
    if !submission_variant
      flash[:error] = "Unknown submission variant {submission_type: `#{submission_type}`, tf: `#{config[:tf]}`, species: `#{config[:species]}`}"
      redirect '/'
    end

    ticket = SecureRandom.alphanumeric(10)
    FileUtils.mkdir_p "scene/#{ticket}"
    File.write("scene/#{ticket}/config.json", config.to_json)

    current_user.send_submission(ticket: ticket, submission_variant: submission_variant)
    AMQPManager.schedule_task(ticket: ticket, exchange: submission_type)
    flash[:notice] = "Your submission got id <strong>#{ticket}</strong>."
    redirect '/submissions'
  end
end

get '/submit_motif' do
  submission_variants = SubmissionVariant.where(submission_type: 'motif').all
  haml :submit_motif, locals: {submission_variants: submission_variants}
end
get '/submit_predictions' do
  submission_variants = SubmissionVariant.where(submission_type: 'predictions').all
  haml :submit_predictions, locals: {submission_variants: submission_variants}
end
get '/submissions' do
  haml :submissions
end
