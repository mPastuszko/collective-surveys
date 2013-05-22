# encoding: UTF-8

require 'sinatra'
require 'slim'
require 'json'
require 'securerandom'
require 'redis'

configure do
  enable :sessions
  raise 'Session secret key not fond. Run `rake generate_session_secret` to generate one.' \
    unless File.exists?('session.secret')
  set :session_secret, File.read('session.secret')
  set :db, Redis.new(YAML.load_file('db.yml'))
end

configure :development do
  Slim::Engine.default_options[:pretty] = true
end

configure :test do
  disable :logging
end

get '/' do
  redirect to('/designer')
end

get '/designer' do
  slim :designer_index, :layout => :layout_designer
end

get %r{/designer/(synonyms|homophones|figures)} do |m|
  slim "designer_#{m}".to_sym, :layout => :layout_designer
end
