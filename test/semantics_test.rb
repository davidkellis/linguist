$: << File.expand_path('../../lib', __FILE__)
require 'test/unit'
require "linguist"

class SemanticsTest < Test::Unit::TestCase
  def test_calculator_language

    # these modules implement the semantic actions
    mod_e_plus_e = Module.new do
      def eval
        lhs.eval + rhs.eval
      end
    end
    mod_e_minus_e = Module.new do
      def eval
        lhs.eval - rhs.eval
      end
    end
    mod_e_multiply_e = Module.new do
      def eval
        lhs.eval * rhs.eval
      end
    end
    mod_e_divide_e = Module.new do
      def eval
        lhs.eval / rhs.eval
      end
    end
    mod_n = Module.new do
      def eval
        text.to_i
      end
    end

    # Now we implement the grammar
    # E -> E + E
    # E -> E - E
    # E -> E * E
    # E -> E / E
    # E -> N
    # N -> '0'
    # N -> '1'
    # ...
    # N -> '8'
    # N -> '9'
    calculator_grammar = Linguist::Grammar.new(:E) do
      e_plus_e = production(:E, seq(label(:E, :lhs), '+', label(:E, :rhs)))
      e_minus_e = production(:E, seq(label(:E, :lhs), '-', label(:E, :rhs)))
      e_multiply_e = production(:E, seq(label(:E, :lhs), '*', label(:E, :rhs)))
      e_divide_e = production(:E, seq(label(:E, :lhs), '/', label(:E, :rhs)))
      e_n = production(:E, :N)
      production(:N, '0'..'9')

      # semantic actions
      bind(e_plus_e, mod_e_plus_e)
      bind(e_minus_e, mod_e_minus_e)
      bind(e_multiply_e, mod_e_multiply_e)
      bind(e_divide_e, mod_e_divide_e)
      bind(e_n, mod_n)

      # disambiguation rules
      prioritize(e_multiply_e, e_plus_e)
      prioritize(e_multiply_e, e_minus_e)
      prioritize(e_divide_e, e_plus_e)
      prioritize(e_divide_e, e_minus_e)
      # I'd like to be able to write this:
      # prioritize([e_multiply_e, e_divide_e], [e_plus_e, e_minus_e])

      associate_equal_priority_group(:left, [e_plus_e, e_minus_e])
      associate_equal_priority_group(:left, [e_multiply_e, e_divide_e])
      #I'd like to be able to write this, and not have to worry about the priority of the nodes:
      # associate(:left, [e_plus_e, e_minus_e, e_multiply_e, e_divide_e])
    end

    parser = Linguist::PracticalEarleyEpsilonParser.new(calculator_grammar.to_bnf)
    
    assert parser.match?("1+2-3+4*5-6*7+8*8+9")
    parse_forest = parser.parse("1+2-3+4*5-6*7+8*8+9")
    assert_equal 1, parse_forest.count
    tree = parse_forest.annotated_parse_tree(calculator_grammar.semantic_actions)
    assert_equal 51, tree.eval
  end
end