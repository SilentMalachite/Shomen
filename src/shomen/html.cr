module Shomen
  module HTML
    def self.escape(text : String) : String
      text.gsub('&', "&amp;")
        .gsub('<', "&lt;")
        .gsub('>', "&gt;")
        .gsub('"', "&quot;")
        .gsub('\'', "&#39;")
    end
  end
end
