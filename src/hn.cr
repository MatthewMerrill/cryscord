require "http/client"
require "json"

module HackerNews
  class Item
    getter id
    getter deleted
    getter type
    getter by
    getter time
    getter text
    getter dead
    getter parent
    getter poll
    getter kids
    getter url
    getter score
    getter title
    getter parts
    getter descendants
    
    def initialize(
      @id : Int64,
      @deleted : Bool,
      @type : String,
      @by : String,
      @time : Int64,
      @text : String,
      @dead : Bool,
      @parent : Int64 | Nil,
      @poll : Int64 | Nil,
      @kids : Array(Int64) | Nil,
      @url : String | Nil,
      @score : Int64 | Nil,
      @title : String | Nil,
      @parts : Array(Int64) | Nil,
      @descendants : Int64 | Nil
      )
    end
    
    # TODO: This is more idiomatic.
    # def self.new(pull : JSON::PullParser)
    # end
    
    def self.from_id(id : Int64)
      res = HTTP::Client.get("https://hacker-news.firebaseio.com/v0/item/#{id}.json?print=pretty")
      Item.from_json(res.body)
    end
    
    def self.from_json(json : String)
      json = JSON.parse(json)
      Item.new(
      json["id"].as_i64,
      (json["deleted"]?.try &.as_bool) || false,
      json["type"].as_s,
      json["by"].as_s,
      json["time"].as_i64,
      (json["text"]?.try &.as_s? || ""),
      (json["dead"]?.try &.as_bool || false),
      json["parent"]?.try &.as_i64,
      (json["poll"]?.try &.as_i64),
      json["kids"]?.try &.as_a.try &.map(&.as_i64),
      json["url"]?.try &.as_s,
      json["score"]?.try &.as_i64,
      json["title"]?.try &.as_s,
      json["parts"]?.try &.as_a.try &.map(&.as_i64),
      json["descendants"]?.try &.as_i64,
      )
    end
  end
  
  def HackerNews.topstories()
    res = HTTP::Client.get("https://hacker-news.firebaseio.com/v0/topstories.json?print=pretty")
    JSON.parse(res.body).as_a[0,10].map(&.as_i64).map(&->Item.from_id(Int64))
  end
end
