require 'rubygems'
require 'sinatra'

require 'main'
require 'logger'

root_dir = File.dirname(__FILE__)

log = File.new('log/sinatra.log', 'a')
$stdout.reopen(log)
$stderr.reopen(log)

set :environment, :production
set :root,  root_dir
set :logging, true
set :app_file, File.join(root_dir, 'portal.rb')
disable :run

run Sinatra::Application
