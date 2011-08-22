$: << File.expand_path('../../lib', __FILE__)
require 'test/unit'
require "linguist"

class RecognitionTest < Test::Unit::TestCase
  def test_language1
    # S -> 'a' S | 'b'
    grammar = Linguist::Grammar.new do
      production(:s, seq('a', :s))
      production(:s, 'b')
    end
    
    parser = Linguist::PracticalEarleyEpsilonParser.new(grammar.to_bnf)
    
    assert parser.match?("aaaab")
    assert_equal [[:s, "a", [:s, "a", [:s, "a", [:s, "a", [:s, "b"]]]]]], parser.parse_trees
  end
  
  def test_lr1
    # S -> S B | A
    # A -> 'a'
    # B -> 'b'
    grammar = grammar {
      production(:s, seq(:s, :b))
      production(:s, :a)
      production(:a, 'a')
      production(:b, 'b')
    }
    
    parser = Linguist::PracticalEarleyEpsilonParser.new(grammar.to_bnf)
    
    assert parser.match?("abbbbbb")
    assert_equal 1, parser.parse_trees.length
  end
  
  def test_lr2
    # S -> T | A
    # T -> S B
    # A -> 'a'
    # B -> 'b'
    grammar = grammar {
      production(:s, :t)
      production(:s, :a)
      production(:t, seq(:s, :b))
      production(:a, 'a')
      production(:b, 'b')
    }
    
    parser = Linguist::PracticalEarleyEpsilonParser.new(grammar.to_bnf)
  
    assert parser.match?("abbbbbbbbbbbbb")
    assert_equal 1, parser.parse_trees.length
  end
end