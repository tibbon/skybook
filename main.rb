require "rubygems"
require "bundler/setup"
require "fb_graph"
require 'sinatra'
require "oauth"
require 'crack/json'
require "sequel"
require "logger"
enable :sessions
set :erb, :trim => '-'

settings = YAML::load_file('config.yaml')

$consumer_key = settings["facebook_settings"]["consumer_key"]
$consumer_secret = settings["facebook_settings"]["consumer_secret"]
oauth_token = settings["facebook_settings"]["oauth_token"]
oauth_token_secret = settings["facebook_settings"]["oauth_token_secret"]
cookie_secret = settings["cookie_settings"]["secret"]
mysql_user = settings["mysql_settings"]["user"]
mysql_password = settings["mysql_settings"]["password"]
mysql_database = settings["mysql_settings"]["database"]

set :session_secret, cookie_secret

DB = Sequel.connect(:adapter => 'mysql', :user => mysql_user, :host => 'localhost', :database => mysql_database,:password => mysql_password, :logger => Logger.new('log/db.log'))

unless DB.table_exists? :users
  DB.create_table :users do
    primary_key :id
    String :skype_name
    String :access_token
    String :fb_name
    Integer :fb_id
  end
end

class User < Sequel::Model
end

fb_auth = FbGraph::Auth.new("202145019859718", "c5d027600e88eda6d1e5db7bec9c1f40")
fb_auth.access_token # => Rack::OAuth2::AccessToken

helpers do
  def check_command_word(skype_text)
    if !skype_text.match(/^\.\w*/).nil?
      return skype_text.match(/^\.\w*/).to_s
    else
      return nil
    end
  end 
  
  def fix_links(skype_text)
    skype_text.scan(/\S+">(\S+)<\/a>/).each do |link|
      linktext = link[0]
      skype_text.gsub!(/<a href=\"\S+#{linktext}<\/a>/, linktext) 
    end
    return skype_text
  end
end



get '/facebook_login' do
  session[:user] = params[:user]
  client = fb_auth.client
  client.redirect_uri = "http://fbdev.imvox.com/callback"
  redirect to client.authorization_uri(:scope => [:email, :offline_access])
end


get '/callback' do
  user = session[:user]
  client = fb_auth.client
  client.authorization_code = params[:code]
  access_token = client.access_token!  # => Rack::OAuth2::AccessToken
  access_token = access_token.to_s
  unless User[:skype_name => user, :access_token => access_token]
    User.create(:skype_name => user, :access_token => access_token)
  end
  FbGraph::User.me(access_token).fetch # => FbGraph::User. I think this just acts as a check here. Call again. 
  redirect to '/instructions'
end


get '/instructions' do
  return erb :instructions
end

post '/' do
  @skype_text = params[:text].to_s 
  @skype_name = params[:user].to_s
  @action = params[:action].to_s
  @skype_text = fix_links(@skype_text)
  
  @command_word = check_command_word(@skype_text)

  if @command_word == ".help" 
    @return_text = "Help data"
    return erb :one_line_output
  end

  if @action == "NEW" 
    @return_text = "Click on the following link to authorize Skybook: http://fbdev.imvox.com/facebook_login?user=" + @skype_name.to_s
    return erb :one_line_output
  end
  
  unless User[:skype_name => @skype_name]
    @return_text = "Click on the following link to authorize Skybook: http://fbdev.imvox.com/facebook_login?user=" + @skype_name.to_s
    return erb :one_line_output
  end
  
  current_user = User[:skype_name => @skype_name]
  facebook_client = FbGraph::User.me(current_user.access_token).fetch
  
  facebook_client.feed!(
    :message => @skype_text
  )
  
  @return_text = @skype_text
  return erb :one_line_output

end

