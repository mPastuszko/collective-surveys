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

configure :test do
  disable :logging
end
