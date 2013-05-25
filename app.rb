# encoding: UTF-8

require 'sinatra'
require 'slim'
require 'json'
require 'securerandom'
require 'redis'

configure do
  enable :sessions
  raise 'Session secret key not fond. Run `rake session.secret` to generate one.' \
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

def db
 settings.db
end

get '/' do
  redirect to('/designer')
end

get '/designer' do
  slim :designer_index, :layout => :layout_designer
end

get %r{/designer/(synonyms|homophones|figures)} do |m|
  @base_words = db.get "#{m}:base_words"
  @survey_link = session[m] && session[m][:survey_link]
  slim "designer_#{m}".to_sym, :layout => :layout_designer
end

post %r{/designer/(synonyms|homophones)/plan} do |m|
  db.set "#{m}:base_words", params[:base_words]
  redirect to("/designer/#{m}#plan")
end

post %r{/designer/(synonyms|homophones)/publish} do |m|
  saved = false
  until saved
    survey_id = SecureRandom.urlsafe_base64
    saved = db.setnx "survey:#{survey_id}:surveyer_name", params[:surveyer_name]
  end
  base_words = db.get "#{m}:base_words"
  db.set "survey:#{survey_id}:base_words", base_words
  db.set "survey:#{survey_id}:module", m
  db.sadd "#{m}:surveys", survey_id
  session[m] ||= {}
  session[m][:survey_link] = url("/survey/#{survey_id}")
  redirect to("/designer/#{m}#publish")
end

get '/survey' do
  page = case params[:page].to_i
    when 1
      :survey_questions_homophones
    when 2
      :survey_demographic_info
    when 3
      :survey_thanks
    when 4
      :survey_already_participated
    else
      :survey_welcome
    end
  slim page, :layout => :layout_survey
end

