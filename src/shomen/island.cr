require "./route"

# Serves the official JavaScript and the island modules. Each file is read
# at compile time, so the binary carries it wherever it runs and nothing
# builds it.
module Shomen::Island
  SOURCE       = {{ read_file("#{__DIR__}/assets/shomen.js") }}
  CONTENT_TYPE = "text/javascript; charset=utf-8"

  class Script < Shomen::Route
    method GET
    path "/shomen.js"

    struct Input
    end

    def call(input : Input) : Shomen::Response
      Shomen::Response.new(200, CONTENT_TYPE, SOURCE)
    end
  end

  # Defines, where it is called, the route <Name>Island that serves the
  # module of the island name at /islands/<name>.js. file is read at
  # compile time, relative to the file that calls this. shomen.js loads the
  # module for an element with data-shomen-island="<name>" and calls its
  # default with the element.
  macro script(name, file, dir = __DIR__)
    {% unless name.is_a?(StringLiteral) && name =~ /\A[a-z][a-z0-9-]*\z/ %}
      {% name.raise "island name must be a string literal of lower-case letters, digits, and '-' that starts with a letter, got #{name}" %}
    {% end %}
    {% unless file.is_a?(StringLiteral) %}
      {% file.raise "island file must be a string literal" %}
    {% end %}
    {% file_path = file.starts_with?("/") ? file : "#{dir.id}/#{file.id}" %}
    {% source = read_file?(file_path) %}
    {% unless source %}
      {% file.raise "island file not found: #{file_path.id}" %}
    {% end %}
    # A part after '-' that starts with a letter is capitalized; any other
    # part keeps a '_' in front, so two names never share a class.
    {% class_name = name.split("-").map { |part| part =~ /\A[a-z]/ ? part.capitalize : "_#{part.id}" }.join("") %}
    class {{class_name.id}}Island < ::Shomen::Route
      method GET
      path {{"/islands/#{name.id}.js"}}

      SOURCE = {{source}}

      struct Input
      end

      def call(input : Input) : ::Shomen::Response
        ::Shomen::Response.new(200, ::Shomen::Island::CONTENT_TYPE, SOURCE)
      end
    end
  end
end
