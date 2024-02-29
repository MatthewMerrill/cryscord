require "http/web_socket"
require "http/client"
require "json"
require "log"

module Cryscord
  VERSION = "0.1.0"

  LIB_NAME = "Cryscord"
  API_BASE = "https://discord.com/api/v10"
  GATEWAY_CONNECT = "wss://gateway.discord.gg/?v10&encodingg=json"

  class BotConfig

    getter name : String
    getter host : String
    getter version : String
    getter token : String
    getter intents : Int32

    def initialize(@name : String, @host : String, @version : String, @token : String, @intents : Int32)
    end

    def headers(upload = false)
      headers = HTTP::Headers.new\
        .add("User-Agent", "#{name} (#{host} #{version})")\
        .add("Authorization", "Bot #{@token}")
      if upload
        headers.add("Content-Type", "application/json")
      end
      headers
    end

    def socket_endpoint() : String
      return GATEWAY_CONNECT
      # return "wss://gateway.discord.gg"
      # if (res = HTTP::Client.get(API_BASE + "/gateway/bot", headers)).status_code != 200
      #   p! res
      #   raise Exception.new("/gateway/bot failed: #{res.status_code}")
      # end
      # res = JSON.parse(res.body)
      # res["url"].as_s
    end
  end

  class Bot

    getter config : BotConfig
    getter application_id : String

    @gateway_session : GatewaySession
    @slash_handlers = Hash(String, (SlashInteraction -> Nil)).new

    def self.connect(name : String, token : String, intents : Int32)
      config = BotConfig.new(name, token, intents)
      gateway_session = GatewaySession.new config
      res = HTTP::Client.get("#{API_BASE}/applications/@me", config.headers)
      unless res.status_code == 200
        raise Exception.new("failed /applications/@me: " + res.body)
      end
      application_id = JSON.parse(res.body)["id"].as_s
      Bot.new config, gateway_session, application_id
    end

    def initialize(
        @config : BotConfig,
        @gateway_session : GatewaySession,
        @application_id : String)
      @gateway_session.on_event do |e| handle_event e end
    end

    def slash_command(name, description, &handler : SlashInteraction -> Nil)
      body = JSON.build do |json|
        json.object do
          json.field "name", name
          json.field "type", 1 # SLASH COMMANDS
          json.field "description", description
        end
      end
      res = HTTP::Client.post(
          "https://discord.com/api/v10/applications/#{@application_id}/commands",
          @config.headers(true),
          body)
      unless res.status_code == 200 || res.status_code == 201
        p! res
        raise Exception.new("Failed to create slash command: " + res.body)
      end
      res = JSON.parse(res.body)
      @slash_handlers[res["id"].as_s] = handler
    end

    def handle_event(e : JSON::Any)
      # https://discord.com/developers/docs/interactions/application-commands#slash-commands-example-interaction
      unless e["type"].as_i == 2
        puts "Ignoring event of type #{e["type"].as_i}"
        return
      end
      @slash_handlers[e["data"]["id"].as_s].call SlashInteraction.new(self, e)
    end

    def run()
      @gateway_session.try &.run
    end
  end

  class GatewaySession

    # https://discord.com/developers/docs/topics/opcodes-and-status-codes
    GATEWAY_EVENT_DISPATCH = 0
    GATEWAY_EVENT_HEARTBEAT_PULSE = 1
    GATEWAY_EVENT_IDENTIFY = 2
    GATEWAY_EVENT_HELLO = 10
    GATEWAY_EVENT_HEARTBEAT_ACK = 11

    property sequence : (Int32 | Nil) = nil

    def initialize(@config : BotConfig)
      @ws = HTTP::WebSocket.new(@config.socket_endpoint, @config.headers)
      @ws.on_message do |msg| on_message msg end
      @ws.on_close do |msg| @sequence = -1 end
    end

    def on_event(&@on_event : JSON::Any -> Nil)
    end

    def on_message(message : String)
      msg = JSON.parse(message)
      if last_sequence = msg["s"].as_i?
        @sequence = last_sequence
      end
      case msg["op"].as_i
      when GATEWAY_EVENT_DISPATCH
        case msg["t"].as_s
        when "READY"
          Log.info { "[#{LIB_NAME}][WS] Bot is ready!" }
        when "INTERACTION_CREATE"
          begin
            @on_event.try &.call msg["d"]
          rescue ex
            puts "Error handling event!"
            puts ex.message
            pp! ex.backtrace
            pp! msg
          end
        else
          puts "Unknown event type " + msg["t"].as_s
        end
      when GATEWAY_EVENT_HELLO
        sleep_ms = msg["d"]["heartbeat_interval"].as_i
        spawn do
          loop do
            sleep (70 * sleep_ms // 100) // 1000
            if sequence == -1
              break
            end
            Log.debug { "[#{LIB_NAME}][WS] Heartbeat sending..." }
            heartbeat_msg = JSON.build do |json|
              json.object do
                json.field "op", GATEWAY_EVENT_HEARTBEAT_PULSE
                json.field "d", sequence
              end
            end
            @ws.send heartbeat_msg
          end
        end
        outmsg = %({\
          "op":2,\
          "d":{\
            "token":"#{@config.@token}",\
            "properties":{\
              "os":"linux",\
              "browser":"#{@config.@name}",\
              "device":"#{@config.@name}"\
            },\
            "compress":false,\
            "intents":#{@config.@intents}\
          }\
        })
        @ws.send outmsg
      when GATEWAY_EVENT_HEARTBEAT_ACK
        Log.debug { "[#{LIB_NAME}][WS] Heartbeat acked!" }
      else
        Log.warn { "[#{LIB_NAME}][WS] Unhandled msg!" }
        unhandled_msg = msg
        p! unhandled_msg
      end 
    end

    def run()
      @ws.run
    end
  end

  class SlashInteraction
    def initialize(@bot : Bot, @e : JSON::Any)
      @id = e["id"].as_s
      @token = e["token"].as_s
    end

    def reply(content : String, suppress_embeds = true)
      body = JSON.build do |json|
        json.object do
          json.field "type", 4
          json.field "data", do
            json.object do
              json.field "content", content
              if suppress_embeds
                # SUPPRESS_EMBEDS message flag
                json.field "flags", 4
              end
              json.field "allowed_mentions" do
                json.object do
                  json.field "parse" do
                    json.array do end
                  end
                end
              end
            end
          end
        end
      end
      res = HTTP::Client.post(
        "#{API_BASE}/interactions/#{@id}/#{@token}/callback",
        @bot.config.headers(true),
        body)
      unless res.status_code == 200 || res.status_code == 201
        raise Exception.new "Interaction reply failed with status_code #{res.status_code}: #{res.body}"
      end
    end
  end
end
