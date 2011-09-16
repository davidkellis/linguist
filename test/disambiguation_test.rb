# encoding: UTF-8

$: << File.expand_path('../../lib', __FILE__)
require 'test/unit'
require "linguist"
# require 'perftools'

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
    parse_forest = parser.parse("5+6")
    assert parse_forest.count == 1
    
    # 2 trees
    parse_forest = parser.parse("5+6-7")
    assert parse_forest.count == 2
    
    # 5 trees
    parse_forest = parser.parse("5+6-3^2")
    assert parse_forest.count == 5
    
    g.prefer(e_exp_e, e_plus_e)
    g.prefer(e_exp_e, e_minus_e)
    g.associate_equal_priority_group(:left, [e_plus_e, e_minus_e])
    g.associate_equal_priority_group(:right, [e_exp_e])
    
    # 1 tree
    parse_forest = parser.parse("5-6-3^2")
    assert parse_forest.count == 1
    
    # 1 tree
    parse_forest = parser.parse("5+6-3^2")
    assert parse_forest.count == 1

    # 1 tree
    parse_forest = parser.parse("5-6-3^2^5")
    assert parse_forest.count == 1
  end

  def test_disambiguated_tree
    g = Linguist::Grammar.new
    e_multiply_e = g.production(:E, g.seq(:E, '*', :E))
    e_divide_e = g.production(:E, g.seq(:E, '/', :E))
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

    # 1 trees
    parse_forest = parser.parse("1-2")
    assert parse_forest.count == 1
    
    # 2 trees
    parse_forest = parser.parse("1-2*3")
    assert parse_forest.count == 2
    
    # 5 trees
    parse_forest = parser.parse("1-2*3^4")
    assert parse_forest.count == 5
    
    # 14 trees
    parse_forest = parser.parse("1-2*3^4+5")
    assert parse_forest.count == 14

    # 42 trees - takes ~10 seconds to run
    parse_forest = parser.parse("1-2*3^4+5/6")
    assert parse_forest.count == 42
    
    # 132 trees - takes ~10 minutes to run
    parse_forest = parser.parse("1-2*3^4+5/6*7")   # (1-(2*(3^4)))+((5/6)*7)
    assert parse_forest.count == 132

    g.prefer(e_exp_e, e_multiply_e)
    g.prefer(e_exp_e, e_divide_e)
    g.prefer(e_multiply_e, e_plus_e)
    g.prefer(e_multiply_e, e_minus_e)
    g.prefer(e_divide_e, e_plus_e)
    g.prefer(e_divide_e, e_minus_e)
    
    # addition and subtraction are left associative but they are the same priority, so we group them together
    g.associate_equal_priority_group(:left, [e_plus_e, e_minus_e])
    
    # multiplication and divisino are left associative but they are the same priority, so we group them together
    g.associate_equal_priority_group(:left, [e_divide_e, e_multiply_e])
    g.associate_equal_priority_group(:right, [e_exp_e])

    parse_forest = parser.parse("1-2")
    assert parse_forest.count == 1
    
    parse_forest = parser.parse("1-2*3")
    assert parse_forest.count == 1
    
    parse_forest = parser.parse("1-2*3^4")
    assert parse_forest.count == 1
    
    # "1-2*3^4+5" => (1-(2*(3^4)))+5
    expected_parse_tree = [:E,
                            [:E,
                              [:E,
                                [:N, '1']], 
                              '-',
                              [:E,
                                [:E,
                                  [:N, '2']], 
                                '*',
                                [:E,
                                  [:E,
                                    [:N, '3']], 
                                  '^',
                                  [:E,
                                    [:N, '4']]]]], 
                            '+',
                            [:E,
                              [:N, '5']]]
    parse_forest = parser.parse("1-2*3^4+5")
    assert parse_forest.count == 1
    assert_equal expected_parse_tree, parse_forest.first[0].to_sexp

    # "1-2*3^4+5/6" => (1-(2*(3^4)))+(5/6)
    expected_parse_tree = [:E,
                            [:E,
                              [:E,
                                [:N, '1']], 
                              '-',
                              [:E,
                                [:E,
                                  [:N, '2']], 
                                '*',
                                [:E,
                                  [:E,
                                    [:N, '3']], 
                                  '^',
                                  [:E,
                                    [:N, '4']]]]], 
                            '+',
                            [:E,
                              [:E,
                                [:N, '5']], 
                              '/',
                              [:E,
                                [:N, '6']]]]
    parse_forest = parser.parse("1-2*3^4+5/6")
    assert parse_forest.count == 1
    assert_equal expected_parse_tree, parse_forest.first[0].to_sexp

    # "1-2*3^4+5/6*7" => (1-(2*(3^4)))+((5/6)*7)
    expected_parse_tree = [:E,
                            [:E,
                              [:E,
                                [:N, '1']], 
                              '-',
                              [:E,
                                [:E,
                                  [:N, '2']], 
                                '*',
                                [:E,
                                  [:E,
                                    [:N, '3']], 
                                  '^',
                                  [:E,
                                    [:N, '4']]]]], 
                            '+',
                            [:E,
                              [:E,
                                [:E,
                                  [:N, '5']], 
                                '/',
                                [:E,
                                  [:N, '6']]], 
                              '*',
                              [:E,
                                [:N, '7']]]]
    # PerfTools::CpuProfiler.start("/tmp/disambiguation_test") do
    parse_forest = parser.parse("1-2*3^4+5/6*7")   # (1-(2*(3^4)))+((5/6)*7)
    # end
    assert parse_forest.count == 1
    assert_equal expected_parse_tree, parse_forest.first[0].to_sexp
  end

  def test_reject_filter
    g = Linguist::Grammar.new
    g.production(:ID, g.plus(:CHAR))     # ID -> CHAR+
    g.production(:CHAR, 'a')
    g.production(:CHAR, 'b')
    g.production(:CHAR, 'c')
    g.start = :ID

    # pp g.to_bnf

    parser = Linguist::PracticalEarleyEpsilonParser.new(g.to_bnf)

    # 1 trees
    parse_forest = parser.parse("a")
    assert parse_forest.count == 1

    # 1 trees
    parse_forest = parser.parse("ab")
    assert parse_forest.count == 1

    # 1 trees
    parse_forest = parser.parse("abc")
    assert parse_forest.count == 1

    g.reject(:ID, "aaa")
    g.reject(:ID, /c+/)

    # 0 trees
    parse_forest = parser.parse("aaa")
    assert parse_forest.count == 0

    # 0 trees
    parse_forest = parser.parse("c")
    assert parse_forest.count == 0
    
    # 0 trees
    parse_forest = parser.parse("cc")
    assert parse_forest.count == 0
    
    # 0 trees
    parse_forest = parser.parse("ccc")
    assert parse_forest.count == 0
  end
end
