module Readability
  class NodeScore
    property score, element

    def initialize(@score = 0.0, @element = XML.parse_html("<body />"))
    end
  end
end
