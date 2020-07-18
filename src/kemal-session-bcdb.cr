require "uri"
require "json"
require "kemal-session"
require "bcdb"

module Kemal

  class Session
    class BcdbEngine < Engine
      class StorageInstance
        include JSON::Serializable

        macro define_storage(vars)
            {% for name, type in vars %}
              property {{name.id}}s : Hash(String, {{type}}) = Hash(String, {{type}}).new
            {% end %}

          {% for name, type in vars %}
            getter {{name.id}}s

            def {{name.id}}(k : String) : {{type}}
              return @{{name.id}}s[k]
            end

            def {{name.id}}?(k : String) : {{type}}?
              return @{{name.id}}s[k]?
            end

            def {{name.id}}(k : String, v : {{type}})
              @{{name.id}}s[k] = v
            end
          {% end %}

          def initialize; end
        end

        define_storage({
          int: Int32,
          bigint: Int64,
          string: String,
          float: Float64,
          bool: Bool,
          object: Kemal::Session::StorableObject::StorableObjectContainer
        })
      end

      @bcdb  : Bcdb::Client
      @cache : StorageInstance
      @cached_session_id : String
      @expires_at : Int64

      def initialize(unixsocket = "/tmp/bcdb.sock", namespace = "kemal_sessions", key_prefix = "kemal:session:")
        @bcdb = Bcdb::Client.new unixsocket: unixsocket, db: "db", namespace: namespace

        @cache = StorageInstance.new
        @key_prefix = key_prefix
        @cached_session_id = ""
        @expires_at = 0_i64
      end

      def run_gc
        # TODO: when bcdb supports a way to get tags < certain number or so
      end

      def prefix_session(session_id : String)
        "#{@key_prefix}#{session_id}"
      end

      def parse_session_id(key : String)
        key.sub(@key_prefix, "")
      end

      private def expired?(session)
        res = session["tags"]["session_expires"].to_s.to_i64 < Time.utc.to_unix ? true : false
      end

      def load_into_cache(session_id)
        @cached_session_id = session_id
        values = @bcdb.find({"session_id" => prefix_session(session_id)})
        @cache = StorageInstance.new

        if values.size == 0
          @expires_at = Time.utc.to_unix + Session.config.timeout.total_seconds.to_i64
          @bcdb.put(@cache.to_json, {"session_id" => prefix_session(session_id), "session_prefix" => @key_prefix, "session_expires" => @expires_at.to_s})
        else
          session = @bcdb.get(values[0])
          if !expired? session
            @expires_at = session["tags"]["session_expires"].to_s.to_i64
            value = session["data"].as(String)
            @cache = StorageInstance.from_json(value)
          else
            @bcdb.update(values[0], @cache.to_json)
          end
        end
        return @cache
      end

      def save_cache
        session_id = @cached_session_id
        values = @bcdb.find({"session_id" => prefix_session(session_id)})
        @bcdb.update(values[0], @cache.to_json)
      end

      def is_in_cache?(session_id)
        return session_id == @cached_session_id
      end

      def create_session(session_id : String)
        load_into_cache(session_id)
      end

      def get_session(session_id : String)
        
        values = @bcdb.find({"session_id" => prefix_session(session_id)})
        if values.size == 0
          return nil
        end
        session = @bcdb.get(values[0])
        if expired? session
          @bcdb.delete(values[0])
          return nil
        end
        return session["data"].as(String)
      end

      def destroy_session(session_id : String)
        values = @bcdb.find({"session_id" => prefix_session(session_id)})
        if values.size > 0
          @bcdb.delete(values[0])
        end
      end

      # @TODO: find a proper way to do it
      def destroy_all_sessions
        loop do
          ids = @db.find({"session_prefix" => @key_prefix})
            ids.each do |id|
              key = @db.delete(id)
            end
            break if ids.size == "0"
          end
      end

      def all_sessions
        arr = [] of Session

        each_session do |session|
          arr << session
        end

        return arr
      end

      def each_session
        
        loop do
        ids = @db.find({"session_prefix" => @key_prefix})
       
          ids.each do |id|
            key = @db.get(id)["tags"]["session_id"]
            yield Session.new(parse_session_id(key.as(String)))
          end
          break if ids.size == "0"
        end

      end

      macro define_delegators(vars)
        {% for name, type in vars %}
          def {{name.id}}(session_id : String, k : String) : {{type}}
            load_into_cache(session_id) unless is_in_cache?(session_id)
            return @cache.{{name.id}}(k)
          end

          def {{name.id}}?(session_id : String, k : String) : {{type}}?
            load_into_cache(session_id) unless is_in_cache?(session_id)
            return @cache.{{name.id}}?(k)
          end

          def {{name.id}}(session_id : String, k : String, v : {{type}})
            load_into_cache(session_id) unless is_in_cache?(session_id)
            @cache.{{name.id}}(k, v)
            save_cache
          end

          def {{name.id}}s(session_id : String) : Hash(String, {{type}})
            load_into_cache(session_id) unless is_in_cache?(session_id)
            return @cache.{{name.id}}s
          end
        {% end %}
      end

      define_delegators({
        int: Int32,
        bigint: Int64,
        string: String,
        float: Float64,
        bool: Bool,
        object: Kemal::Session::StorableObject::StorableObjectContainer,
      })
    end
  end
end