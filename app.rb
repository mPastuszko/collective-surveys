# encoding: UTF-8

require 'sinatra'
require 'slim'
require 'json'
require 'yaml'
require 'securerandom'
require 'redis'
require 'digest/sha1'

require_relative 'lib/survey_answer.rb'

configure do
  enable :sessions
  raise 'Session secret key not fond. Run `rake session.secret` to generate one.' \
    unless File.exists?('session.secret')
  set :session_secret, File.read('session.secret')
  set :password_hash, File.read('password.secret')
  set :db, Redis.new(YAML.load_file('db.yml'))
  set :figures_path, File.join('upload', 'figures')
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

post '/authenticate' do
  password_valid = (Digest::SHA1.hexdigest(params[:password]) == settings.password_hash)
  session[:username] = params[:username] if password_valid
  redirect to('/designer')
end

before '/designer*' do
  halt slim(:designer_authenticate, :layout => :layout_survey) unless session[:username]
end

get '/designer/logout' do
  session[:username] = nil
  redirect to('/designer')
end

get '/designer' do
  slim :designer_index, :layout => :layout_designer
end

get %r{/designer/(synonyms|homophones|figures)} do |m|
  case m
  when 'synonyms', 'homophones'
    @base_words = db.get "#{m}:base_words"
  when 'figures'
    @figure_sets = figure_sets
  end
  session[m] ||= {}
  @survey_link = session[m][:survey_id] && url("/survey/#{session[m][:survey_id]}")
  @answers = answers(m)
  slim "designer_#{m}".to_sym, :layout => :layout_designer
end

get '/figure/:id/:filename' do |id, filename|
  send_file figure_path(id, filename)
end

post %r{/designer/(synonyms|homophones)/plan} do |m|
  db.set "#{m}:base_words", params[:base_words]
  redirect to("/designer/#{m}#plan")
end

post '/designer/figures/plan' do
  return redirect to("/designer/figures#plan") unless params[:base_figure] and params[:other_figures].last
  id = db.incr "figures:figure_set:id"
  
  figure_set_path = File.join(settings.figures_path, id.to_s)
  FileUtils.mkdir_p(figure_set_path)
  
  File.open(figure_path(id, params[:base_figure][:filename]), 'w') do |file|
    file.write(params[:base_figure][:tempfile].read)
  end
  db.set "figures:figure_set:#{id}:base_figure", params[:base_figure][:filename]
  params[:other_figures].each {|figure|
    File.open(figure_path(id, figure[:filename]), 'w') do |file|
      file.write(figure[:tempfile].read)
    end
    db.sadd "figures:figure_set:#{id}:other_figures", figure[:filename]
  }
  db.sadd "figures:figure_sets", id
  redirect to("/designer/figures#plan")
end

delete '/designer/figures/plan/:id' do |id|
  db.srem "figures:figure_sets", id
  redirect to("/designer/figures#plan")
end

post %r{/designer/(synonyms|homophones|figures)/publish} do |m|
  saved = false
  until saved
    survey_id = SecureRandom.urlsafe_base64
    saved = db.setnx "survey:#{survey_id}:surveyer_name", session[:username]
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
  when 'figures'
    db.sadd "survey:#{survey_id}:figure_sets", db.smembers("#{m}:figure_sets")
  end
  db.sadd "#{m}:surveys", survey_id
  session[m] ||= {}
  session[m][:survey_id] = survey_id
  redirect to("/designer/#{m}#publish")
end

post %r{/designer/(synonyms|homophones|figures)/reset} do |m|
  survey_id = session[m] && session[m][:survey_id]
  db.srem "#{m}:surveys", survey_id
  session[m][:survey_id] = nil
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
  when 'figures'
    data[:figure_sets] = figure_sets("survey:#{survey_id}:figure_sets")
  end
  data
end

def figure_path(set_id, filename)
  File.join(settings.figures_path, set_id.to_s, filename)
end

def figure_sets(source = "figures:figure_sets")
  db.smembers(source).sort.map do |id|
    {
      id: id,
      base_figure: "/figure/#{id}/" + db.get("figures:figure_set:#{id}:base_figure"),
      other_figures: db.smembers("figures:figure_set:#{id}:other_figures") \
        .map { |figure| "/figure/#{id}/#{figure}" } \
        .sort
    }
  end
end

def answers(kind)
  answers = db.smembers("#{kind}:surveys") \
    .map do |survey|
      db.smembers("survey:#{survey}:answers") \
        .map do |answer|
          {
            id: answer,
            surveyer: db.get("survey:#{survey}:surveyer_name"),
            state: db.get("answer:#{answer}:state")
          }
        end
    end.flatten
  finished = answers \
    .select { |answer| answer[:state] == 'finished' } \
    .each { |answer| answer[:answer] = JSON.load(db.get("answer:#{answer[:id]}:answer")) }
  p finished
  surveyers = db.smembers("#{kind}:surveys") \
    .map { |survey| db.get("survey:#{survey}:surveyer_name") } \
    .uniq \
    .sort \
    .map do |surveyer|
      {
        name: surveyer,
        all: answers.select {|a| a[:surveyer] == surveyer },
        finished: finished.select {|a| a[:surveyer] == surveyer }
      }
    end
  {
    all: answers,
    finished: finished,
    surveyers: surveyers
  }
end
