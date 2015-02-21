module.exports = (Module) ->

  FeedSub = require "feedsub"
  shorturl = require "shorturl"
  _ = require "lodash"
  _.str = require "underscore.string"
  color = require "irc-colors"

  class RSSModule extends Module
    shortName: "RSS"
    helpText:
      default: "Watch an RSS feed and send updates to the channel!"
      'rss-remove': "Remove a noisy or old RSS feed!"
    usage:
      default: "rss [title] <interval=10 (minutes)> [url]"
      'rss-remove': "rss-remove [title]"

    feeds: {}

    constructor: (moduleManager) ->
      super moduleManager

      @db = @newDatabase 'feeds'

      generateKey = (server, channel, key) =>
        server + channel + key

      say = (server, channel, msg) =>
        moduleManager.botManager.botHash[server].say channel, msg

      rss = (server, channel, url, title, interval=10, silent=no) =>
        if not _.str.include url, "http"
          say server, channel, "You need to specify a valid URL." unless silent
          return

        key = generateKey server, channel, title
        if @feeds[key]
          say server, channel, "You already have a feed named #{color.bold title}." unless silent
          return

        newFeed = new FeedSub url,
          interval: interval
          autoStart: yes
          emitOnStart: yes
          lastDate: new Date()
          history: 20

        newFeed._isFirst = yes

        @feeds[key] = newFeed

        if not silent then @db.insert {server: server, channel: channel, url: url, title: title, interval: interval}, ->

        newFeed.on "items", (items) =>
          return newFeed._isFirst = no if newFeed._isFirst
          _.each items, (item) =>
            shorturl item.link, (shorturl) =>
              say server, channel, "[#{color.bold title}] (#{shorturl}) #{item.title}"

        say server, channel, "I am now watching #{color.bold title} (#{url}) for posts (check interval: #{interval} minutes)." unless silent

      @addRoute "rss :title :interval *", "core.manage.rss", (origin, route) =>
        interval = parseInt route.params.interval
        if not interval or interval < 1
          @reply origin, "Your interval is invalid, try again."
          return

        rss origin.bot.config.server, origin.channel, route.splats[0], route.params.title, interval

      @addRoute "rss :title *", "core.manage.rss", (origin, route) =>
        rss origin.bot.config.server, origin.channel, route.splats[0], route.params.title

      @addRoute "rss-remove :title", "core.manage.rss", (origin, route) =>
        key = generateKey origin, route.params.title
        @feeds[key]?.stop()
        @feeds[key] = null
        @db.remove {server: origin.bot.config.server, channel: origin.channel, title: route.params.title}, =>
          @reply origin, "Feed #{color.bold route.params.title} stopped."

      @db.findForEach {}, (e, item) ->
        rss item.server, item.channel, item.url, item.title, item.interval, yes

  RSSModule