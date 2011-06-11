$: << File.expand_path('../../lib', __FILE__)
require 'test/unit'
require "linguist"

class RecognitionTest < Test::Unit::TestCase
  def test_epsilon
    # S -> 'a'*
    grammar = Linguist::Grammar.new do
      production(:s, kleene('a'))
    end
    
    pp grammar.to_bnf.non_terminals
    pp grammar.to_bnf.nullable_non_terminals
    
    parser = Linguist::EarleyEpsilonParser.new(grammar.to_bnf)
    
    assert parser.match?("")
    assert parser.match?("a")
    assert parser.match?("aa")
    assert parser.match?("aaa")
    assert parser.match?("aaaaaaaaaaaaaaaaaaaaaaa")
  end

  def test_kleene_star
    # S -> 'a'*
    grammar = Linguist::Grammar.new do
      production(:s, kleene('a'))
    end
    
    parser = Linguist::EarleyEpsilonParser.new(grammar.to_bnf)
    
    assert parser.match?("")
    assert parser.match?("a")
    assert parser.match?("aa")
    assert parser.match?("aaa")
    assert parser.match?("aaaaaaaaaaaaaaaaaaaaaaa")
  end
end