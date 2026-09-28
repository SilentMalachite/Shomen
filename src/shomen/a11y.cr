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
end
