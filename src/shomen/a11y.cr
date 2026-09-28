class Shomen::View
  macro html(lang = nil, &block)
    {% unless lang.is_a?(StringLiteral) %}
      {% raise "html requires lang: as a string literal" %}
    {% end %}
    {% unless lang =~ /^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$/ %}
      {% raise "html lang must look like en or zh-Hant" %}
    {% end %}
    # block.body.stringify drops comments and writes every regex literal as /.../.
    {% stripped = block.body.stringify
         .gsub(/"(?:[^"\\]|\\.)*"/, "\"\"")
         .gsub(/\/(?:\\.|[^\/\n])*\/[a-z]*/, "") %}
    {% count = stripped.scan(/(^|[^.\w])title\s*(\(|do\b)/).size %}
    {% if count != 1 %}
      {% raise "html document must contain exactly one title, found #{count}" %}
    {% end %}
    reset
    @out << "<!DOCTYPE html><html lang=\""
    @out << Shomen::HTML.escape({{lang}})
    @out << "\">"
    {{block.body}}
    @out << "</html>"
    result
  end

  macro button(content = nil, type = nil, **attrs, &block)
    {% allowed = ["submit", "button", "reset"] %}
    {% unless type.is_a?(StringLiteral) && allowed.includes?(type) %}
      {% raise "button requires type: \"submit\" | \"button\" | \"reset\"" %}
    {% end %}
    {% if content && block %}
      {% raise "button takes either text or a block" %}
    {% end %}
    @out << "<button type=\"" << Shomen::HTML.escape({{type}}) << "\""
    {% for key, value in attrs %}
      @out << " " << {{key.id.stringify}} << "=\"" << Shomen::HTML.escape(({{value}}).to_s) << "\""
    {% end %}
    @out << ">"
    {% if content %}
      text({{content}})
    {% elsif block %}
      {{block.body}}
    {% end %}
    @out << "</button>"
  end

  macro img(alt = nil, **attrs)
    {% unless alt.is_a?(StringLiteral) %}
      {% raise "img requires alt: as a string literal" %}
    {% end %}
    @out << "<img alt=\"" << Shomen::HTML.escape({{alt}}) << "\""
    {% for key, value in attrs %}
      @out << " " << {{key.id.stringify}} << "=\"" << Shomen::HTML.escape(({{value}}).to_s) << "\""
    {% end %}
    @out << ">"
  end

  macro inherited
    macro method_added(method)
      ::Shomen::View.check_input_labels(\{{method.body.stringify}}, \{{@type.name.stringify}})
    end
  end

  # method.body.stringify prints one statement per line with two-space
  # indentation, so a label block's extent is found by indentation.
  macro check_input_labels(source, type_name)
    {% lines = source.lines %}
    {% codes = lines.map { |line| line.gsub(/"(?:[^"\\]|\\.)*"/, "\"\"").gsub(/\/(?:\\.|[^\/\n])*\/[a-z]*/, "") } %}
    {% fors = [] of Nil %}
    {% for line, index in lines %}
      {% if codes[index] =~ /(^|[^.\w])label(\(|\s|$)/ %}
        {% for found in line.scan(/\bfor: "((?:[^"\\]|\\.)*)"/) %}
          {% fors << found[1] %}
        {% end %}
      {% end %}
    {% end %}
    {% open = [] of Nil %}
    {% for line, index in lines %}
      {% code = codes[index] %}
      {% indent = line.size - line.gsub(/^ +/, "").size %}
      {% if code.strip == "end" && !open.empty? && open.last >= indent %}
        {% open = open.size == 1 ? [] of Nil : open[0..-2] %}
      {% end %}
      {% if code =~ /(^|[^.\w])label(\(.*\))? do\b/ %}
        {% open << indent %}
      {% elsif code =~ /(^|[^.\w])input(\(|\s*$)/ %}
        {% ok = !open.empty? || line.includes?("type: \"hidden\"") || line.includes?("\"aria-label\": ") %}
        {% unless ok %}
          {% ids = line.scan(/\bid: "((?:[^"\\]|\\.)*)"/) %}
          {% ok = !ids.empty? && fors.includes?(ids[0][1]) %}
        {% end %}
        {% unless ok %}
          {% raise "#{type_name.id} input needs a label: label for: matching id:, a wrapping label, or \"aria-label\"" %}
        {% end %}
      {% end %}
    {% end %}
  end
end
