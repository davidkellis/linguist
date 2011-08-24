$: << File.expand_path('../../lib', __FILE__)
require 'test/unit'
require "linguist"

# class PatternTest < Test::Unit::TestCase
#   def test_nested_alternatives
#     g = grammar
#     p1a = g.production(:s, :a)
#     p1b = g.production(:s, :b)
#     p1c = g.production(:s, :c)
#     p2 = g.production(:a, 'a')
#     p3 = g.production(:b, 'b')
#     p4 = g.production(:c, 'c')
    
#     assert_equal p1.non_terminal, :s
#     assert_equal p1.pattern, [ [:a], [:b], [:c] ]
#   end
# end