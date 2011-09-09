$: << File.expand_path('../../lib', __FILE__)
require 'test/unit'
require "linguist"

class AmbiguityTest < Test::Unit::TestCase
  def test_ambiguous_grammar
    # S -> S S | 'a'
    grammar = Linguist::Grammar.new do
      production(:s, seq(:s, :s))
      production(:s, 'a')
    end
    
    parser = Linguist::PracticalEarleyEpsilonParser.new(grammar.to_bnf)
    
    assert parser.match?("aaaa")

    expected_parse_trees = [
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
          [:s, "a"]], 
        [:s, 
          [:s, "a"], 
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

    parse_forest = parser.parse_forest
    parse_forest.generate_node_alternatives!
    parse_trees = parse_forest.map {|tree, or_nodes| tree.to_sexp }
    assert_equal expected_parse_trees, parse_trees
  end
end