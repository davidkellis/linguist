# encoding: UTF-8

module Linguist
  # This represents an Earley Item.
  # From the Parsing Techniques book:
  #   An Item is a production with a gap in its right-hand side.
  #   The first "half" (the left-hand portion) of the production's right-hand side is the portion of the pattern
  #   that has already been recognized.
  #   The last "half" (the right-hand portion) .
  #   An Earley Item is an Item with an indication of the position of the symbol at which the 
  #   recognition of the recognized part started.
  #   The Item E-->E•QF@3 would be represented using this structure as:
  #   Item.new(:E, [:E], [:Q, :F], 3)
  Item = Struct.new(:non_terminal, :left_pattern, :right_pattern, :position, :production)
  class Item
    def to_s
      "[#{non_terminal} -> #{left_pattern.join(" ")}•#{right_pattern.join(" ")}, #{position}]"
    end
  end
end