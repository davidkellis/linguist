$: << File.expand_path('../../lib', __FILE__)
require 'test/unit'
require "linguist"

class AnyTest < Test::Unit::TestCase
  def test_dot
    # S -> x.z
    grammar = Linguist::Grammar.new(:s) do
      production(:s, seq('x', dot, 'z'))
    end
    
    parser = Linguist::PracticalEarleyEpsilonParser.new(grammar)
    
    assert parser.match?("xyz")
    assert parser.match?("x1z")
    assert parser.match?("x-z")
    assert parser.match?("xzz")
    assert !parser.match?("xz")
    assert !parser.match?("zzz")
  end

  def test_dot_kleene
    # S -> .*
    grammar = Linguist::Grammar.new(:s) do
      production(:s, kleene(dot))
    end
    
    parser = Linguist::PracticalEarleyEpsilonParser.new(grammar)
    
    assert parser.match?("")
    assert parser.match?("a")
    assert parser.match?("ab")
    assert parser.match?("abc")
    assert parser.match?("abcd")
    assert parser.match?("--")
    assert parser.match?("?122j:LKASJDO98D")
  end
end