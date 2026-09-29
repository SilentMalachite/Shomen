require "./view"

# A view of one element to put inside a document, never a document
# itself. A view embeds it; a route sends it alone with render_fragment.
abstract class Shomen::Fragment < Shomen::View
  macro html(*args, **kwargs, &block)
    {% raise "a fragment cannot contain html; use Shomen::View for a document" %}
  end

  abstract def content : Nil

  def to_html : String
    reset
    content
    result
  end
end
