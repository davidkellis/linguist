$: << File.expand_path('../../lib', __FILE__)
require 'test/unit'
require "linguist"

class AmbiguityTest < Test::Unit::TestCase
  def test_ambiguous_grammar
    # S -> S S | 'a'
    grammar = Linguist::Grammar.new do
      production(:s, alt(seq(:s, :s), 'a'))
    end
    
    parser = Linguist::PracticalEarleyEpsilonParser.new(grammar.to_bnf)
    
    assert parser.match?("aaaa")
    pp parser.parse_trees
    # parser.parse_trees.each{|tree| puts tree.to_sexp }
    # assert_equal 5, parser.parse_trees.length
  end
end