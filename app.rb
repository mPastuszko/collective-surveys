# encoding: UTF-8

require 'sinatra'
require 'slim'
require 'json'
require 'securerandom'

configure do
  enable :sessions
  raise 'Session secret key not fond. Run `rake generate_session_secret` to generate one.' \
    unless File.exists?('session.secret')
  set :session_secret, File.read('session.secret')
end

configure :test do
  disable :logging
end
