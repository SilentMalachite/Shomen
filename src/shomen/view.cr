abstract class Shomen::View
  # The path the official JavaScript is served at.
  SCRIPT_PATH = "/shomen.js"

  abstract def to_html : String

  # Subclass constructors in specs do not call super. A class-body
  # initializer still runs; an initialize method would not.
  @out = IO::Memory.new

  def text(value) : Nil
    @out << Shomen::HTML.escape(value.to_s)
  end

  def raw(value : String) : Nil
    @out << value
  end

  def embed(fragment : Shomen::Fragment) : Nil
    @out << fragment.to_html
  end

  protected def result : String
    @out.to_s
  end

  protected def reset : Nil
    @out = IO::Memory.new
  end

  private def open_tag(name : String, attrs) : Nil
    @out << "<" << name
    write_attributes(attrs)
    @out << ">"
  end

  private def close_tag(name : String) : Nil
    @out << "</" << name << ">"
  end

  private def void_tag(name : String, attrs) : Nil
    @out << "<" << name
    write_attributes(attrs)
    @out << ">"
  end

  private def write_attributes(attrs) : Nil
    attrs.each do |key, value|
      @out << " " << key.to_s << "=\"" << Shomen::HTML.escape(value.to_s) << "\""
    end
  end

  {% for name in %w(head body header main footer nav h1 h2 h3 p div span ul ol li a form label textarea title) %}
    def {{name.id}}(content : String, **attrs) : Nil
      open_tag({{name}}, attrs)
      text(content)
      close_tag({{name}})
    end

    def {{name.id}}(**attrs, &) : Nil
      open_tag({{name}}, attrs)
      yield
      close_tag({{name}})
    end
  {% end %}

  def meta(**attrs) : Nil
    void_tag("meta", attrs)
  end

  def input(**attrs) : Nil
    void_tag("input", attrs)
  end

  def csrf_field(token : String) : Nil
    void_tag("input", {type: "hidden", name: "_csrf", value: token})
  end

  # The only script element the DSL writes.
  def shomen_script : Nil
    @out << "<script src=\"" << SCRIPT_PATH << "\" defer></script>"
  end
end
