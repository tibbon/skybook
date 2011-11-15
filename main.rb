require "rubygems"
require "bundler/setup"
require "twitter"
require 'sinatra'
require "oauth"
require 'crack/json'
require "sequel"
require "logger"
enable :sessions
set :erb, :trim => '-'

settings = YAML::load_file('config.yaml')

$consumer_key = settings["twitter_settings"]["consumer_key"]
$consumer_secret = settings["twitter_settings"]["consumer_secret"]
oauth_token = settings["twitter_settings"]["oauth_token"]
oauth_token_secret = settings["twitter_settings"]["oauth_token_secret"]
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
    String :access_secret
    String :twitter_screen_name
    Integer :twitter_id
    Bool :current_account
  end
end

class User < Sequel::Model
  def authorize_to_twitter()
    Twitter.configure do |config|
      config.consumer_key = $consumer_key
      config.consumer_secret = $consumer_secret
      config.oauth_token = self.access_token
      config.oauth_token_secret = self.access_secret
    end
    return Twitter::Client.new
  end
end

helpers do
  def authorize_to_twitter_without_user_create(access_token, access_secret)
    Twitter.configure do |config|
      config.consumer_key = $consumer_key
      config.consumer_secret = $consumer_secret
      config.oauth_token = access_token
      config.oauth_token_secret = access_secret
    end
    return Twitter::Client.new
  end
  
  def get_second_word(word)
    if word.match(/^\S+\s+(\S+)/)
      return word.match(/^\S+\s+(\S+)/)[1]
    else
      return false
    end
  end
  

  def check_command_word(skype_text)
    if !skype_text.match(/^\.\w*/).nil?
      return skype_text.match(/^\.\w*/).to_s
    else
      return nil
    end
  end
  
end

get '/' do
  return "Coming soon"
end

get '/twitter_login' do
  session[:user] = params[:user]
  @user = params[:user]
  @consumer = OAuth::Consumer.new($consumer_key,$consumer_secret,{:site=>"http://twitter.com"})
  @req_token = @consumer.get_request_token(:oauth_callback => "http://twitter.imvox.com/callback")
  session[:request_token] = @req_token.token 
  session[:request_token_secret] = @req_token.secret
  
  if User[:skype_name => @user]
    @auth_url = @req_token.authorize_url + "&force_login=true"
  else
    @auth_url = @req_token.authorize_url 
  end
  #return "@auth_url.to_s"
  redirect to @auth_url
end


get '/callback' do
  @consumer = OAuth::Consumer.new($consumer_key,$consumer_secret,{:site=>"http://twitter.com" })
  @req_token = OAuth::RequestToken.new(@consumer,session[:request_token],session[:request_token_secret])
  @skype_name = session[:user]
  
  @access_token = @req_token.get_access_token
  @twitter = authorize_to_twitter_without_user_create(@access_token.token, @access_token.secret)
  @twitter_user = @twitter.verify_credentials
  @twitter_id = @twitter_user["id_str"].to_i
  @twitter_screen_name = @twitter_user["screen_name"]
  
  if User[:skype_name => @skype_name, :twitter_id => @twitter_id]
    User[:skype_name => @skype_name, :twitter_id => @twitter_id].delete
  end
  User.filter(:skype_name => @skype_name).update(:current_account => false)
  
  current_user = User.create(:skype_name => @skype_name, :access_token => @access_token.token, :access_secret => @access_token.secret, :twitter_screen_name => @twitter_screen_name, :twitter_id => @twitter_id, :current_account => '1')

  redirect to '/instructions'
end


get '/instructions' do
  return erb :instructions
end

post '/initialize' do
  @skype_text = params[:text].to_s 
  @skype_name = params[:user].to_s
  @action = params[:action].to_s
  
  @command_word = check_command_word(@skype_text)

  if @command_word == ".help" 
    @return_text = "<b>Available commands:</b> \r\n <b>.dms</b> - Returns your most recent 5 direct messages \r\n <b>.replies</b> - Returns your most recent 5 mentions \r\n <b>.timeline</b> - Returns the most recent 5 statuses in your timeline \r\n <b>.add</b> - Allows you to add additional Twitter account \r\n <b>.show</b> - Shows all authorized Twitter accounts \r\n <b>.use <i>JohnDoe</i></b> - Switches to a Twitter account you added \r\n <b>.remove <i>JohnDoe</i></b> - Removes Twitter account from Skype. Does not delete your Twitter account. \r\n "
    return erb :one_line_output
  end
  

  if @action == "NEW" 
    @return_text = "Click on the following link to authorize Skychoir: http://twitter.imvox.com/twitter_login?user=" + @skype_name.to_s
    return erb :one_line_output
  end
  
  unless User[:skype_name => @skype_name]
    @return_text = "Click on the following link to authorize Skychoir: http://twitter.imvox.com/twitter_login?user=" + @skype_name.to_s
    return erb :one_line_output
  end
  
  current_user = User[:skype_name => @skype_name, :current_account => "1"]
  
  # This still needs debugged. Should go through EACH match, instead of just one. 
  #Dealing with links in text. Skype screws up the links. 
  @skype_text.scan(/\S+">(\S+)<\/a>/).each do |link|
    linktext = link[0]
    @skype_text.gsub!(/<a href=\"\S+#{linktext}<\/a>/, linktext) 
  end
  
  client = current_user.authorize_to_twitter
 
  if @command_word == ".dms"
    @header = "Last 5 Direct Messages to you:"
    @tweets = client.direct_messages(:count => 5)
    return erb :dms
  elsif @command_word == ".replies"
    @header = "Last 5 mentions of you:"
    @tweets = client.mentions(:count => 5)
    return erb :tweets
  elsif @command_word == ".timeline"
    @header = "Last 5 updates from friends:"
    @tweets = client.home_timeline(:count => 5)
    return erb :tweets
  elsif @command_word == ".removeacct"
    @account = @skype_text.match(/\.removeacct (\S+)/)[1]
    if !@account.nil?
      if User[:twitter_screen_name => @account, :skype_name => @skype_name]
        User[:twitter_screen_name => @account, :skype_name => @skype_name].delete
        @return_text = "Removed your account: " + @account
        return erb :one_line_output
      end
      @return_text = "Unable to remove that user. Is that your user account?"
      return erb :one_line_output
    end
  elsif @command_word == ".use"
    @username = get_second_word(@skype_text)
    if @username
      if User[:skype_name => @skype_name, :twitter_screen_name => @username]
        User.filter(:skype_name => @skype_name).update(:current_account => false)
        User.filter(:skype_name => @skype_name, :twitter_screen_name => @username).update(:current_account => true)
        @return_text = "Now tweeting as: " + @username
        return erb :one_line_output
      else
        @return_text = "That isn't your user account. If you need to add an account type .addacct"
        return erb :one_line_output
      end
    else
      @return_text = "Account name not detected"
      return erb :one_line_output
    end
  elsif @command_word == ".add"
    @return_text = "Click on the following link to authorize Skychoir: http://twitter.imvox.com/twitter_login?user=" + @skype_name.to_s
    return erb :one_line_output
  elsif @command_word == ".show"
    @accounts = User.filter(:skype_name => @skype_name)
    return erb :accounts
  else
        
    @tweet_text = @skype_text.slice!(0, 240)
    
    if @tweet_text.match(/^(d)\s+\@?\S+/)
      if @tweet_text.match(/^(d)\s+\@?\S+/).captures[0].downcase == 'd'
        @destination_name = @tweet_text.match(/^d\s+\@?(\S+)/).captures[0]
        @dm_text = @tweet_text.match(/^d\s+\@?(\S+)/).post_match
        
        begin
          client.direct_message_create(@destination_name, @dm_text)
          return "text: Direct Messaged: " + @destination_name
        rescue Twitter::Forbidden
          return "text: You cannot DM users who are not following you"
        rescue
          return "text: Some odd error occurred"
        end
      end
    end
    
    if @tweet_text.match(/^follow\s+\@?\S+/)
      if @tweet_text.match(/^(follow)\s+\@?\S+/).captures[0].downcase == 'follow'
        @new_friend = @tweet_text.match(/^follow\s+\@?(\S+)/).captures[0]
        client.follow(@new_friend)
        return "text: Followed: "+ @new_friend
      end
    end
    
    if @tweet_text.match(/^unfollow\s+\@?\S+/)
      if @tweet_text.match(/^(unfollow)\s+\@?\S+/).captures[0].downcase == 'unfollow'
        @old_friend = @tweet_text.match(/^unfollow\s+\@?(\S+)/).captures[0]
        client.unfollow(@old_friend)
        return "text: Unfollowed: "+ @old_friend
      end
    end
    
    begin
      client.update(@tweet_text)
    rescue
        @return_text = "Twitter has a problem. Try again"
        return erb :one_line_output
    end
      @return_text = @tweet_text + "\' posted to Twitter as: " + current_user.twitter_screen_name
      return erb :one_line_output
  end
    
    
  
    #@return_text = @action.class
    #return erb :one_line_output
  
end

