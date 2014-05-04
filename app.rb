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
require 'csv'

require_relative 'lib/survey_answer.rb'
require_relative 'lib/word_processor.rb'

configure do
  use Rack::Session::Cookie, :expire_after => 60*60*24*30, #30 days in seconds
                             :secret => File.read('session.secret')
  set :protection, :except => [:frame_options, :ip_spoofing]
  raise 'Session secret key not fond. Run `rake session.secret` to generate one.' \
    unless File.exists?('session.secret')
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

get %r{/designer/(synonyms|homophones|figures)/import$} do |m|
  @module = m.to_sym
  @module_name = module_name(m)
  slim :designer_import, :layout => :layout_designer
end

post %r{/designer/(synonyms|homophones|figures)/import$} do |m|
  @module = m.to_sym
  @module_name = module_name(m)
  @file = params[:file][:tempfile]
  @csv = CSV.read(@file, :col_sep => ';')
  slim :designer_import_preview, :layout => :layout_designer
end

post %r{/designer/(synonyms|homophones|figures)/import/verified$} do |m|
  csv = JSON[params[:answers]]
  answers = csv[1..-1]
  surveyer_name = csv[1][1]
  base_data = csv[0][6..-1]
  survey_id = create_survey(m, surveyer_name, '', base_data)
  answers.each do |answer|
    params = {
      gender: answer[4],
      age: answer[5],
      answer: answer[6..-1],
      state: answer[2]
    }
    answer = SurveyAnswer.new(db, survey_id, nil)
    answer.update(params)
  end
  redirect to("/designer/#{m}")
end

get %r{/designer/(synonyms|homophones|figures)/answers-(finished|all).csv} do |m, subset|
  content_type :csv
  display_filter = params[:display]
  answers = answers(m, display_filter)[subset.to_sym]
  normalize_answers(m, answers)
    .map { |row| row.map{|column| "\"#{column}\""}.join(';') }
    .join($/)
end

get %r{/designer/(synonyms|homophones|figures)/results-(finished|all).csv} do |m, subset|
  content_type :csv
  display_filter = params[:display]
  answers = answers(m, display_filter)[subset.to_sym]
  results = word_results(m, answers)
  results = sort_word_results(results, 'alpha')
  spreadsheet = results
    .inject([]) { |rows, word_set|
      rows << [
        [''] * 2,
        'Odch. std.',
        'Skośność',
        'Kurtoza',
        '',
        (1..6).to_a.map {|i| "FAS #{i}" },
        '',
        (1..word_set[:similar_distributions].size).to_a.map {|i| "Podob. #{i}" },
        '',
        word_set[:enabled_words_histogram].map {|word| word[:frequency] }
      ].flatten
      rows << [
        word_set[:base_word],
        '',
        word_set[:statistics_first_6][:standard_deviation].round(2),
        word_set[:statistics_first_6][:skewness].round(2),
        word_set[:statistics_first_6][:kurtosis].round(2),
        '',
        word_set[:fas_first_6].map {|e| e.round(2) },
        '',
        word_set[:similar_distributions].map(&:first),
        '',
        word_set[:enabled_words_histogram].map {|word| word[:word] }
      ].flatten
      rows
    }
  longest_word_set = spreadsheet.map(&:size).max
  spreadsheet
    .map { |word_set|
      word_set.fill('', word_set.size...longest_word_set)
    }
    .transpose
    .map { |row| row.map{|column| column.is_a?(Numeric) ? column.to_s.sub('.', ',') : "\"#{column}\"" }.join(';') }
    .join($/)
end

get %r{/designer/(synonyms|homophones|figures)/results-part} do |m|
  @module = m.to_sym
  display_filter = params[:display]
  @answers = answers(m, display_filter)
  @results = case m
    when 'synonyms', 'homophones'
      sort_word_results(word_results(m, @answers[:finished]), params[:sort] ||= 'alpha')
    when 'figures'
      figure_results(@answers[:finished])
    end
  @ages = @answers[:finished].map { |a| a[:age].to_i }.reject(&:zero?)
  @avg_age = (@ages.inject(:+).to_f / @ages.size)
    .round(2)
  @genders = @answers[:finished].map { |a|
      a[:gender] && a[:gender].to_sym
    }
    .compact
    .inject(Hash.new(0)) { |counter, a|
      counter[a] += 1; counter
    }
  @genders[:all] = @genders.values.inject(:+)
  results_part = case m
    when 'synonyms', 'homophones'
      'words'
    when 'figures'
      'figures'
    end
  slim "_designer_results_#{results_part}".to_sym, :layout => false
end

post %r{/designer/(synonyms|homophones)/merge-words} do |m|
  merged_words = JSON[db.get("#{m}:merged_words") || '{}']
  params[:merge].each_pair do |base_word, words|
    merged_words[base_word] ||= []
    merged_words[base_word] << words.keys if words.size > 1
  end
  db.set("#{m}:merged_words", merged_words.to_json)
  200
end

post %r{/designer/(synonyms|homophones)/split-words} do |m|
  base_word = params[:base_word]
  word = params[:word]
  merged_words_set = JSON[db.get("#{m}:merged_words") || '{}']
  merged_words = merged_words_set[base_word]
  if merged_words
    merged_words.delete_if {|ws| ws.include? word }
    db.set("#{m}:merged_words", merged_words_set.to_json)
  end
  200
end

post %r{/designer/(synonyms|homophones)/disable-enable-word} do |m|
  p params
  base_word = params[:base_word]
  word = params[:word]
  disable = (params[:disable] == 'true')
  disabled_words_set = JSON[db.get("#{m}:disabled_words") || '{}']
  disabled_words = (disabled_words_set[base_word] ||= [])
  if disable
    disabled_words << word
  else
    disabled_words.delete(word)
  end
  db.set("#{m}:disabled_words", disabled_words_set.to_json)
  200
end

get %r{/designer/(synonyms|homophones|figures)} do |m|
  @module = m.to_sym
  case m
  when 'synonyms', 'homophones'
    @base_words = db.get "#{m}:base_words"
  when 'figures'
    @figure_sets = figure_sets
  end
  session[m] ||= {}
  session[m][:survey_id] = db.smembers("#{m}:surveys")
    .find {|s| db.get("survey:#{s}:surveyer_name") == session[:username] }
  @survey_link = session[m][:survey_id] && url("/survey/#{session[m][:survey_id]}")
  @survey_instructions = session[m][:survey_id] && db.get("survey:#{session[m][:survey_id]}:instructions")
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
  return redirect to("/designer/figures#plan") unless params[:figures].last
  id = db.incr "figures:figure_set:id"

  figure_set_path = File.join(settings.figures_path, id.to_s)
  FileUtils.mkdir_p(figure_set_path)

  params[:figures].each do |figure|
    File.open(figure_path(id, figure[:filename]), 'w') do |file|
      file.write(figure[:tempfile].read)
    end
    db.sadd "figures:figure_set:#{id}:figures", figure[:filename]
  end
  db.sadd "figures:figure_sets", id
  redirect to("/designer/figures#plan")
end

delete '/designer/figures/plan/:id' do |id|
  db.srem "figures:figure_sets", id
  redirect to("/designer/figures#plan")
end

post %r{/designer/(synonyms|homophones|figures)/publish} do |m|
  survey_id = create_survey(m, session[:username], params[:instructions])
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
  @answer = SurveyAnswer.new(db, survey_id, answer_id)
  @data = survey_data(survey_id)
  session[:survey][survey_id] = @answer.id
  slim "survey_#{@answer.state}".to_sym, :layout => :layout_survey
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

def create_survey(kind, surveyer_name, instructions, base_data = nil)
  saved = false
  until saved
    survey_id = SecureRandom.urlsafe_base64
    saved = db.setnx "survey:#{survey_id}:surveyer_name", surveyer_name
  end
  db.set "survey:#{survey_id}:kind", kind
  db.set "survey:#{survey_id}:instructions", instructions
  case kind
  when 'synonyms', 'homophones'
    base_words = base_data || db.get("#{kind}:base_words")
      .lines
      .to_a
      .map(&:chomp)
      .reject{ |e| e == '' }
    db.set "survey:#{survey_id}:base_words", base_words.to_json
  when 'figures'
    db.sadd "survey:#{survey_id}:figure_sets", db.smembers("#{kind}:figure_sets")
  end
  db.sadd "#{kind}:surveys", survey_id
  survey_id
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
  data[:instructions] = db.get "survey:#{survey_id}:instructions"
  data
end

def figure_path(set_id, filename)
  File.join(settings.figures_path, set_id.to_s, filename)
end

def figure_sets(source = "figures:figure_sets")
  db.smembers(source).sort.map do |id|
    {
      id: id,
      figures: db.smembers("figures:figure_set:#{id}:figures")
        .map { |figure|
          p figure
          {
            name: figure,
            url: "/figure/#{id}/#{figure}"
          }
        }
        .sort { |f1, f2| f1[:name] <=> f2[:name] }
    }
  end
end

def answers(kind, display_filter = nil)
  answers = db.smembers("#{kind}:surveys")
    .map do |survey|
      surveyer = db.get("survey:#{survey}:surveyer_name")
      if display_filter.nil? or display_filter[surveyer]
        db.smembers("survey:#{survey}:answers")
          .map { |answer|
            {
              id: answer,
              surveyer: surveyer,
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
          }
      else
        []
      end
    end
    .flatten
    .sort {|a, b| a[:id] <=> b[:id] }
  finished = answers
    .select { |answer| answer[:state] == 'finished' and answer[:answer_raw] }
    .each { |answer| answer[:answer] = JSON.load(answer[:answer_raw]) }
  surveyers = db.smembers("#{kind}:surveys")
    .map { |survey| db.get("survey:#{survey}:surveyer_name") }
    .uniq
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
    [header] + answers
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
          and (a[:answer][index] || '').strip.downcase
      end
    end
  when 'figures'
    [header]
  end
end

def word_results(kind, answers)
  words_to_merge = JSON[db.get("#{kind}:merged_words") || '{}']
  disabled_words = JSON[db.get("#{kind}:disabled_words") || '{}']
  results = normalize_answers(kind, answers)
    .transpose
    .slice(6..-1)
    .map do |word_set|
      base_word, answered_words = word_set.first, word_set[1..-1]
      answered_words_ascii = WordProcessor::normalize_national_chars(answered_words)
      answered_words_clean = WordProcessor::clean(answered_words_ascii)
      answered_words_histogram = WordProcessor::histogram(answered_words_clean)
      merged_words_histogram = WordProcessor::merge(answered_words_histogram, words_to_merge[base_word] || [])
      all_words_histogram = WordProcessor::disable(merged_words_histogram, disabled_words[base_word] || [])
      enabled_words_histogram = all_words_histogram.reject {|w| w[:disabled] }
      {
        base_word: word_set.first,
        histogram: all_words_histogram,
        enabled_words_histogram: enabled_words_histogram,
        statistics: WordProcessor::statistics(enabled_words_histogram),
        statistics_first_6: WordProcessor::statistics(enabled_words_histogram[0...6]),
        fas_first_6: WordProcessor::fas(enabled_words_histogram[0...6])
      }
    end

  # Add similar histograms information
  histograms_difference_matrix = WordProcessor::histograms_difference_matrix(results, 6)
  results.each do |word_set|
    word = word_set[:base_word]
    word_set[:similar_distributions] = WordProcessor::similar_distributions(word, histograms_difference_matrix, 30)
  end
  results
end

def figure_results(answers)

end

def questions(answers)
  answers.inject(Set.new) {|questions, a| questions.merge(a[:question]) }
end

def sort_word_results(results, criterion)
  if criterion
    results.sort { |a, b|
      b[:statistics_first_6][criterion.to_sym] <=> a[:statistics_first_6][criterion.to_sym]
    }
  else
    results
  end
end

def module_name(m)
  {
    synonyms: 'Synonimy',
    homophones: 'Homofony',
    figures: 'Figury'
  }[m.to_sym]
end
