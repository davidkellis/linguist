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
    expected_parse_trees = [
      [:s, 
        [:s, 
          [:s, "a"], 
          [:s, "a"]], 
        [:s, 
          [:s, "a"], 
          [:s, "a"]]],
      
      [:s, 
        [:s, "a"], 
        [:s, 
          [:s, "a"], 
          [:s, 
            [:s, "a"], 
            [:s, "a"]]]],
      
      [:s, 
        [:s, "a"], 
        [:s, 
          [:s, 
            [:s, "a"], 
            [:s, "a"]], 
          [:s, "a"]]],
      
      [:s, 
        [:s, 
          [:s, "a"], 
          [:s, 
            [:s, "a"], 
            [:s, "a"]]], 
        [:s, "a"]],
      
      [:s, 
        [:s, 
          [:s, 
            [:s, "a"], 
            [:s, "a"]], 
          [:s, "a"]], 
        [:s, "a"]]
    ]

    assert_equal expected_parse_trees, parser.parse_trees
  end
end