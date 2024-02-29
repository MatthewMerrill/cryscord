require "./cryscord"
require "./hn"
require "http/client"

config = Cryscord::Bot.connect "HNBot", "mattmerr.com", "1.0", ENV["BOT_TOKEN"], 37376
 
def as_md_preview(item : HackerNews::Item)
  # TODO: bracks in title or parens in url bad
  comment_suffix = "[(Link)](<https://news.ycombinator.com/item?id=#{item.id}>)"
  item.descendants.try do |descendants|
    comment_suffix = "[(#{descendants} comments)](<https://news.ycombinator.com/item?id=#{item.id}>)"
  end
  "(#{score || "?"}) [#{item.title}](#{item.url}) | #{comment_suffix}"
end

config.slash_command "hackernews", "Top HN posts!", do |inter|
  inter.reply HackerNews.topstories.map(&->as_md_preview(HackerNews::Item)).join("\n")
end

config.run
