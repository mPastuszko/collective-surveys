# encoding: UTF-8

require 'sinatra'
require 'slim'
require 'json'
require 'yaml'
require 'securerandom'
require 'redis'

require_relative 'lib/survey_answer.rb'

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
  db.set "survey:#{survey_id}:kind", m
  case m
  when 'synonyms', 'homophones'
    base_words = db.get("#{m}:base_words") \
      .lines \
      .to_a \
      .map(&:chomp) \
      .reject{ |e| e == '' }
    db.set "survey:#{survey_id}:base_words", base_words.to_json
  end
  db.sadd "#{m}:surveys", survey_id
  session[m] ||= {}
  session[m][:survey_link] = url("/survey/#{survey_id}")
  redirect to("/designer/#{m}#publish")
end

get '/survey/:id' do |survey_id|
  not_found unless db.exists("survey:#{survey_id}:surveyer_name")
  session[:survey] ||= {}
  answer_id = session[:survey][survey_id]
  answer = SurveyAnswer.new(db, survey_id, answer_id)
  @data = survey_data(survey_id)
  session[:survey][survey_id] = answer.id
  slim "survey_#{answer.state}".to_sym, :layout => :layout_survey
end

post '/survey/:id' do |survey_id|
  answer_id = session[:survey][survey_id]
  answer = SurveyAnswer.new(db, survey_id, answer_id)
  answer.update(params)
  redirect to("/survey/#{survey_id}")
end

not_found do
  slim :not_found, :layout => :layout_survey
end

def survey_data(survey_id)
  data = {}
  kind = db.get "survey:#{survey_id}:kind"
  case kind
  when 'synonyms', 'homophones'
    data[:base_words] = JSON.load(db.get("survey:#{survey_id}:base_words"))
  end
  data
end
