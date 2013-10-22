# encoding: UTF-8

require 'sinatra'
require 'slim'
require 'json'
require 'yaml'
require 'securerandom'
require 'redis'
require 'digest/sha1'
require 'set'
require 'statsample'

require_relative 'lib/survey_answer.rb'

configure do
  enable :sessions
  set :protection, :except => [:frame_options, :ip_spoofing]
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

helpers do
  def badge_for_frequency(frequency)
    case frequency
    when 1
      ''
    when 2..10
      'badge-warning'
    else
      'badge-important'
    end
  end
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

get %r{/designer/(synonyms|homophones|figures)/results-(finished|all).csv} do |m, subset|
  content_type :csv
  answers = answers(m)[subset.to_sym]
  normalize_answers(m, answers) \
    .map { |row| row.map{|column| "\"#{column}\""}.join(';') } \
    .join($/)
end

get %r{/designer/(synonyms|homophones|figures)} do |m|
  case m
  when 'synonyms', 'homophones'
    @base_words = db.get "#{m}:base_words"
  when 'figures'
    @figure_sets = figure_sets
  end
  session[m] ||= {}
  session[m][:survey_id] = db.smembers("#{m}:surveys") \
    .find {|s| db.get("survey:#{s}:surveyer_name") == session[:username] }
  @survey_link = session[m][:survey_id] && url("/survey/#{session[m][:survey_id]}")
  @answers = answers(m)
  @results = results(m, @answers[:finished])
  @ages = @answers[:finished].map { |a| a[:age].to_i }
  @avg_age = (@ages.inject(:+).to_f / @answers[:finished].size)
    .round(2)
  @genders = @answers[:finished].map { |a|
      a[:gender].to_sym
    }.inject(Hash.new(0)) { |counter, a|
      counter[a] += 1; counter
    }
  @genders[:all] = @genders.values.inject(:+)
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
            state: db.get("answer:#{answer}:state"),
            kind: kind.to_s,
            gender: db.get("answer:#{answer}:gender"),
            age: db.get("answer:#{answer}:age"),
            question: (case kind
            when 'synonyms', 'homophones'
              tmp = db.get("survey:#{survey}:base_words") and JSON.load(tmp).map(&:strip)
            when 'figures'
              db.smembers("survey:#{survey}:figure_sets")
            end),
            answer_raw: db.get("answer:#{answer}:answer")
          }
        end
    end \
    .flatten \
    .sort {|a, b| a[:id] <=> b[:id] }
  finished = answers \
    .select { |answer| answer[:state] == 'finished' and answer[:answer_raw] } \
    .each { |answer| answer[:answer] = JSON.load(answer[:answer_raw]) }
  surveyers = db.smembers("#{kind}:surveys") \
    .map { |survey| db.get("survey:#{survey}:surveyer_name") } \
    .uniq \
    .map do |surveyer|
      {
        name: surveyer,
        all: answers.select {|a| a[:surveyer] == surveyer },
        finished: finished.select {|a| a[:surveyer] == surveyer }
      }
    end.sort {|a, b| b[:finished].size <=> a[:finished].size }
  {
    all: answers,
    finished: finished,
    surveyers: surveyers
  }
end

def normalize_answers(kind, answers)
  questions = questions(answers).to_a.sort
  header = ['Nr', 'Ankieter', 'Stan', 'Rodzaj', 'Płeć', 'Wiek'] + questions
  case kind
  when 'synonyms', 'homophones'
    [header] + answers \
      .sort {|a, b| a[:id].to_i <=> b[:id].to_i } \
      .map do |a|
      [
        a[:id],
        a[:surveyer],
        a[:state],
        a[:kind],
        a[:gender],
        a[:age].to_i,
      ] + questions.map do |q|
        a[:answer] \
          and index = a[:question].index(q) \
          and a[:answer][index].strip.downcase
      end
    end
  when 'figures'
    [header]
  end
end

def results(kind, answers)
  normalize_answers(kind, answers) \
    .transpose \
    .slice(6..-1) \
    .map do |words|
      words_statistics = *words[1..-1] \
        .reject(&:nil?) \
        .inject(Hash.new(0)) { |counter, word| counter[word] += 1; counter } \
        .to_a \
        .sort {|a, b| b.last <=> a.last }
      {
        base_word: words.first,
        histogram: words_statistics,
        statistics: statistics(words_statistics)
      }
    end
end

def questions(answers)
  answers.inject(Set.new) {|questions, a| questions.merge(a[:question]) }
end

def statistics(histogram)
  scale = histogram.map(&:last).to_scale
  {
    standard_deviation: scale.standard_deviation_sample,
    skewness: scale.skew,
    kurtosis: scale.kurtosis
  }
end
