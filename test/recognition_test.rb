$: << File.expand_path('../../lib', __FILE__)
require 'test/unit'
require "linguist"

class RecognitionTest < Test::Unit::TestCase
  def test_language1
    # S -> 'a' S | 'b'
    grammar = Linguist::Grammar.new do
      production(:s, alt(seq('a', :s), 'b'))
    end
    
    parser = Linguist::PracticalEarleyEpsilonParser.new(grammar.to_bnf)
    
    assert parser.match?("aaaaaaaab")
  end
  
  def test_lr1
    # S -> S B | A
    # A -> 'a'
    # B -> 'b'
    grammar = grammar {
      production(:s, alt(seq(:s, :b), :a))
      production(:a, 'a')
      production(:b, 'b')
    }
    
    parser = Linguist::PracticalEarleyEpsilonParser.new(grammar.to_bnf)
    
    assert parser.match?("abbbbbb")
  end
  
  def test_lr2
    # S -> T | A
    # T -> S B
    # A -> 'a'
    # B -> 'b'
    grammar = grammar {
      production(:s, alt(:t, :a))
      production(:t, seq(:s, :b))
      production(:a, 'a')
      production(:b, 'b')
    }
    
    parser = Linguist::PracticalEarleyEpsilonParser.new(grammar.to_bnf)
  
    assert parser.match?("abbbbbbbbbbbbb")
  end
end