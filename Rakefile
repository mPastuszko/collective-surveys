require 'bundler/setup'
require 'securerandom'

desc 'Run app in development mode with auto restart after file changes'
task :run do
  sh "rerun --pattern *.rb --no-growl ruby app.rb"
end

desc 'Generate session secret key'
file 'session.secret' do
  File.open('session.secret', 'w') do |f|
    f << SecureRandom.base64(64)
  end
  puts 'session.secret has been generated.'
end
