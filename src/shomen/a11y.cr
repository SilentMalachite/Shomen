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

  # Runs once after the program is parsed, so an input can match a label
  # anywhere in the same view: its own methods, its parent views, and the
  # modules they include.
  macro finished
    {% for view in Shomen::View.all_subclasses %}
      {% sources = [] of Nil %}
      {% for owner in [view] + view.ancestors %}
        {% unless owner == Shomen::View || Shomen::View.ancestors.includes?(owner) %}
          {% for method in owner.methods %}
            {% sources << method.body.stringify %}
          {% end %}
        {% end %}
      {% end %}
      ::Shomen::View.check_input_labels({{sources}}, {{view.name.stringify}})
    {% end %}
  end

  # method.body.stringify writes every block as do ... end, and a block with
  # one statement on a single line, so a label block's extent is found by
  # counting the keywords that open and close a nesting level.
  macro check_input_labels(sources, type_name)
    {% fors = [] of Nil %}
    {% for source in sources %}
      {% for line in source.lines %}
        {% code = line.gsub(/"(?:[^"\\]|\\.)*"/, "\"\"").gsub(/\/(?:\\.|[^\/\n])*\/[a-z]*/, "") %}
        {% if code =~ /(^|[^.\w])(self\.)?label(\(|\s|$)/ %}
          {% for found in line.scan(/\bfor: "((?:[^"\\]|\\.)*)"/) %}
            {% fors << found[1] %}
          {% end %}
        {% end %}
      {% end %}
    {% end %}
    {% for source in sources %}
      {% depth = 0 %}
      {% open = [] of Nil %}
      {% for line in source.lines %}
        {% code = line.gsub(/"(?:[^"\\]|\\.)*"/, "\"\"").gsub(/\/(?:\\.|[^\/\n])*\/[a-z]*/, "").gsub(/(?<![.\w])self\./, "") %}
        {% wrapped = nil %}
        {% after_label = false %}
        {% for token in code.scan(/(?<![.\w:@$])(label(?=\(| do\b)|input(?=\(|\s*$)|do|end|if|unless|while|until|case|begin)(?![\w?!:])/) %}
          {% word = token[1] %}
          {% if word == "do" %}
            {% if after_label %}
              {% open << depth %}
            {% end %}
            {% depth = depth + 1 %}
          {% elsif word == "end" %}
            {% depth = depth - 1 %}
            {% if !open.empty? && open.last == depth %}
              {% open = open.size == 1 ? [] of Nil : open[0..-2] %}
            {% end %}
          {% elsif word == "input" %}
            {% if wrapped == nil %}
              {% wrapped = !open.empty? %}
            {% end %}
          {% elsif word != "label" %}
            {% depth = depth + 1 %}
          {% end %}
          {% after_label = word == "label" %}
        {% end %}
        {% unless wrapped == nil %}
          {% ok = wrapped || line.includes?("type: \"hidden\"") || line =~ /"aria-label(ledby)?": (?!"")/ %}
          {% unless ok %}
            {% ids = line.scan(/\bid: "((?:[^"\\]|\\.)*)"/) %}
            {% ok = !ids.empty? && fors.includes?(ids[0][1]) %}
          {% end %}
          {% unless ok %}
            {% hint = line =~ /\btype: "(submit|reset|button|image)"/ ? "; for a submit, reset, button, or image control, use button instead" : "" %}
            {% raise "#{type_name.id} input needs a label: a label whose string literal for: matches the input's string literal id:, a wrapping label, or a non-empty \"aria-label\" or \"aria-labelledby\"#{hint.id}" %}
          {% end %}
        {% end %}
      {% end %}
    {% end %}
  end
end
