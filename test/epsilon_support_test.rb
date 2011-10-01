$: << File.expand_path('../../lib', __FILE__)
require 'test/unit'
require "linguist"

class RecognitionTest < Test::Unit::TestCase
  def test_kleene_star
    # S -> 'a'*
    grammar = Linguist::Grammar.new(:s) do
      production(:s, kleene('a'))
    end
    
    parser = Linguist::PracticalEarleyEpsilonParser.new(grammar.to_bnf)
    
    assert parser.match?("")
    assert parser.match?("a")
    assert parser.match?("aa")
    assert parser.match?("aaa")
    assert parser.match?("aaaaaaaaaaaaaaaaaaaaaaa")
  end

  def test_optional
    # S -> 'a'*
    grammar = Linguist::Grammar.new(:s) do
      production(:s, optional('a'))
    end
    
    parser = Linguist::PracticalEarleyEpsilonParser.new(grammar.to_bnf)
    
    assert parser.match?("")
    assert parser.match?("a")
    assert !parser.match?("aa")
  end
end