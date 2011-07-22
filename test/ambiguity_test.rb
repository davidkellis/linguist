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
    
    assert parser.match?("aaa")
    
    # pp parser.completed_list
  end
end