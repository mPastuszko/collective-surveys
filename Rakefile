require 'bundler/setup'
require 'securerandom'
require 'digest/sha1'

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

desc 'Set authentication password'
file 'password.secret' do
  File.open('password.secret', 'w') do |f|
    print "Password: "
    f << Digest::SHA1.hexdigest(STDIN.gets.chomp)
  end
  puts 'password.secret has been created.'
end
