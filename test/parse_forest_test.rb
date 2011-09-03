$: << File.expand_path('../../lib', __FILE__)
require 'test/unit'
require "linguist"

class ParseForestTest < Test::Unit::TestCase
  def test_alternative_generation
    # this tests the parse forest for the grammar:
    # S -> S S | 'a'
    # with the input 'aaaa'

    nodes = [
      Linguist::ParseForest::Node.new(Linguist::Production.new(:s, ['a']), 0, 1),
      Linguist::ParseForest::Node.new(Linguist::Production.new(:s, ['a']), 1, 2),
      Linguist::ParseForest::Node.new(Linguist::Production.new(:s, [:s, :s]), 0, 2),
      Linguist::ParseForest::Node.new(Linguist::Production.new(:s, ['a']), 2, 3),
      Linguist::ParseForest::Node.new(Linguist::Production.new(:s, [:s, :s]), 1, 3),
      Linguist::ParseForest::Node.new(Linguist::Production.new(:s, [:s, :s]), 0, 3),
      Linguist::ParseForest::Node.new(Linguist::Production.new(:s, ['a']), 3, 4),
      Linguist::ParseForest::Node.new(Linguist::Production.new(:s, [:s, :s]), 2, 4),
      Linguist::ParseForest::Node.new(Linguist::Production.new(:s, [:s, :s]), 1, 4),
      Linguist::ParseForest::Node.new(Linguist::Production.new(:s, [:s, :s]), 0, 4)
    ]

    s_0_1, s_1_2, s_0_2, s_2_3, s_1_3, s_0_3, s_3_4, s_2_4, s_1_4, s_0_4 = nodes

    parse_forest = Linguist::ParseForest.new(nodes, [s_0_4])
    
    s_0_4_derivations = [
      [s_0_1, s_1_4],
      [s_0_2, s_2_4],
      [s_0_3, s_3_4]
    ]
    assert_equal s_0_4_derivations, parse_forest.generate_alternatives(s_0_4)

    s_0_1_derivations = [
      [ Linguist::ParseForest::TerminalNode.new('a', 0, 1) ]
    ]
    assert_equal s_0_1_derivations, parse_forest.generate_alternatives(s_0_1)

    s_1_4_derivations = [
      [s_1_2, s_2_4],
      [s_1_3, s_3_4]
    ]
    assert_equal s_1_4_derivations, parse_forest.generate_alternatives(s_1_4)

    s_2_4_derivations = [
      [s_2_3, s_3_4]
    ]
    assert_equal s_2_4_derivations, parse_forest.generate_alternatives(s_2_4)

    s_0_3_derivations = [
      [s_0_1, s_1_3],
      [s_0_2, s_2_3]
    ]
    assert_equal s_0_3_derivations, parse_forest.generate_alternatives(s_0_3)

    s_3_4_derivations = [
      [ Linguist::ParseForest::TerminalNode.new('a', 3, 4) ]
    ]
    assert_equal s_3_4_derivations, parse_forest.generate_alternatives(s_3_4)

    s_1_2_derivations = [
      [ Linguist::ParseForest::TerminalNode.new('a', 1, 2) ]
    ]
    assert_equal s_1_2_derivations, parse_forest.generate_alternatives(s_1_2)

    s_1_3_derivations = [
      [s_1_2, s_2_3]
    ]
    assert_equal s_1_3_derivations, parse_forest.generate_alternatives(s_1_3)

    s_2_3_derivations = [
      [ Linguist::ParseForest::TerminalNode.new('a', 2, 3) ]
    ]
    assert_equal s_2_3_derivations, parse_forest.generate_alternatives(s_2_3)
  end
end