HTTPS          = require 'https'
Request        = require 'request'
{EventEmitter} = require 'events'
Package        = require '../package'
Hubot          = require 'hubot'

class Typetalk extends Hubot.Adapter
  # override
  send: (envelope, strings...) ->
    for string in strings
      @bot.Topic(envelope.room).create string, {}, (err, data) =>
        @robot.logger.error "Typetalk send error: #{err}" if err?

  # override
  reply: (envelope, strings...) ->
    envelope.is_reply = true
    @send envelope, strings.map((str) -> "@#{envelope.user.name} #{str}")...

  # override
  run: ->
    options =
      clientId: process.env.HUBOT_TYPETALK_CLIENT_ID
      clientSecret: process.env.HUBOT_TYPETALK_CLIENT_SECRET
      rooms: process.env.HUBOT_TYPETALK_ROOMS

    bot = new TypetalkStreaming options, @robot
    @bot = bot

    @emit 'connected'

exports.use = (robot) ->
  new Typetalk robot

class TypetalkStreaming extends EventEmitter
  constructor: (options, @robot) ->
    unless options.clientId? and options.clientSecret? and options.rooms?
      @robot.logger.error \
        'Not enough parameters provided. ' \
        + 'Please set client id, client secret and rooms'
      process.exit 1

    @clientId = options.clientId
    @clientSecret = options.clientSecret
    @rooms = options.rooms.split ','
    @host = 'typetalk.in'

  Topics: (callback) ->
    @get '/topics', "", callback

  Topic: (id) ->
    get: (opts, callback) =>
      @get "/topics/#{id}", "", callback

    create: (message, opts, callback) =>
      data =
        message: message
      @post "/topics/#{id}", data, callback

  get: (path, body, callback) ->
    @request "GET", path, body, callback

  post: (path, body, callback) ->
    @request "POST", path, body, callback

  put: (path, body, callback) ->
    @request "PUT", path, body, callback

  delete: (path, body, callback) ->
    @request "DELETE", path, body, callback

  updateAccessToken: (callback) ->
    logger = @robot.logger

    options =
      url: "https://#{@host}/oauth2/access_token"
      form:
        client_id: @clientId
        client_secret: @clientSecret
        grant_type: 'client_credentials'
        scope: 'my,topic.read,topic.post'
      headers:
        'User-Agent': "#{Package.name} v#{Package.version}"

    Request.post options, (err, res, body) =>
      if err
        logger.error "Typetalk HTTPS response error: #{err}"
        if callback
          callback err, {}

      if res.statusCode >= 400
        throw new Error "Typetalk API returned unexpected status code: " \
          + "#{res.statusCode}"

      json = try JSON.parse body catch e then body or {}
      @accessToken = json.access_token
      @refreshToken = json.refresh_token

      if callback
        callback null, json

  request: (method, path, body, callback) ->
    logger = @robot.logger

    req = (err, data) =>
      options =
        url: "https://#{@host}/api/v1#{path}"
        method: method
        headers:
          Authorization: "Bearer #{@accessToken}"
          'User-Agent': "#{Package.name} v#{Package.version}"

      if method is 'POST'
        options.form = body
      else
        options.body = body

      Request options, (err, res, body) =>
        if err
          logger.error "Typetalk response error: #{err}"
          if callback
            callback err, {}

        if res.statusCode >= 400
          @updateAccessToken req

        if callback
          json = try JSON.parse body catch e then body or {}
          callback null, json

    if @accessToken
      req()
    else
      @updateAccessToken req

