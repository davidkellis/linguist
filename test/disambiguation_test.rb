# encoding: UTF-8

$: << File.expand_path('../../lib', __FILE__)
require 'test/unit'
require "linguist"

class DisambiguationTest < Test::Unit::TestCase
  def test_disambiguation_filters
    g = Linguist::Grammar.new
    e_plus_e = g.production(:E, g.seq(:E, '+', :E))
    e_minus_e = g.production(:E, g.seq(:E, '-', :E))
    e_exp_e = g.production(:E, g.seq(:E, '^', :E))
    g.production(:E, :N)
    g.production(:N, '0')
    g.production(:N, '1')
    g.production(:N, '2')
    g.production(:N, '3')
    g.production(:N, '4')
    g.production(:N, '5')
    g.production(:N, '6')
    g.production(:N, '7')
    g.production(:N, '8')
    g.production(:N, '9')
    
    parser = Linguist::PracticalEarleyEpsilonParser.new(g.to_bnf)

    # 1 tree
    parse_forrest = parser.parse("5+6")
    assert parse_forrest.count == 1
    
    # 2 trees
    parse_forrest = parser.parse("5+6-7")
    assert parse_forrest.count == 2
    
    # 5 trees
    parse_forrest = parser.parse("5+6-3^2")
    assert parse_forrest.count == 5
    
    g.prefer(e_exp_e, e_plus_e)
    g.prefer(e_exp_e, e_minus_e)
    g.associate_equal_priority_group(:left, [e_plus_e, e_minus_e])
    g.associate_equal_priority_group(:right, [e_exp_e])
    
    # 1 tree
    parse_forrest = parser.parse("5-6-3^2")
    assert parse_forrest.count == 1
    
    # 1 tree
    parse_forrest = parser.parse("5+6-3^2")
    assert parse_forrest.count == 1

    # 1 tree
    parse_forrest = parser.parse("5-6-3^2^5")
    assert parse_forrest.count == 1
  end
end
