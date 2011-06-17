require 'parsers/earley'    # only for the definition of Item

module Linguist
  # PracticalEarleyParser implements the Earley algorithm as described by Aycock and Horspool
  # in "Practical Earley Parsing" (http://webhome.cs.uvic.ca/~nigelh/Publications/PracticalEarleyParsing.pdf)
  class PracticalEarleyParser
    attr_reader :grammar
    attr_reader :list
  
    def initialize(bnf_grammar)
      @grammar = bnf_grammar
    
      @list = []
    end
  
    def reset
      @list = []
    end
  
    def match?(input)
      reset
      recognize(input.chars)
    end
  
    def parse(input)
      reset
      recognize(input.chars)
      parse_trees
    end
  
    # @param alternatives is an array of pattern sequences, where each pattern sequence is 
    #                     an array of terminals and non-terminals.
    # @return A UniqueArray containing Items, each of the form [non_terminal -> •alternative, position],
    #         for every alternative sequence in +alternatives+
    def construct_initial_item_set(non_terminal, alternatives, position)
      UniqueArray.new(alternatives.map {|pattern| Item.new(non_terminal, [], pattern, position) })
    end
  
    def build_initial_itemset
      list[0] = construct_initial_item_set(grammar.start, grammar.alternatives(grammar.start), 0)
    end
  
    # This is the driver method that invokes the scanner, predictor, and completer for every item
    # in every item list
    def recognize(token_stream)
      build_initial_itemset

      token_stream.each_with_index do |token, position|
        # if the previous invocation of this block did not populate list[position], then break out, because the parse has failed
        break if list[position].nil?
      
        # examine each item in list[position] only once...
        i = 0
        while i < list[position].size
          item = list[position][i]
        
          scan(token, item, position + 1)
          predict(item, position)
          complete(item, position)
        
          i += 1
        end
      end

      # run the predictor and completer on the last set in list, because it hasn't been predicted or completed yet.
      i = 0
      count = token_stream.count
      if list[count]
        while i < list[count].size
          item = list[count][i]
      
          predict(item, count)
          complete(item, count)
      
          i += 1
        end
      end
    
      # list.with_index{|arr,i| puts i; pp arr }
    
      # If the item set that resulted from processing the last token in the input contains an item 
      # S -> ...•@1, that is, an item spanning the entire input and reducing to the start symbol,
      # we have found a valid parse!
      (list[token_stream.count] || []).any? do |item|
        item.non_terminal == grammar.start &&
        item.right_pattern.empty? &&
        item.position == 0
      end
    end
  
    # this runs the scanner
    # This implements the following rule from Practical Earley Parsing:
    # SCANNER. If [A → ...•a..., j] is in S[i] and a=x[i+1], add [A → ...a•..., j] to S[i+1].
    def scan(token, item, destination_position)
      # if item is of the form [A -> ...•token..., j], then we add [A -> ...token•..., j] to list[destination_position]
      if item.right_pattern.first == token ||       # we just saw token in the token stream
         item.right_pattern.first == Pattern::DOT   # this matches the ANY/DOT token in the token stream
        # the part before the • was already recognized and now token is recognized;
        # consequently, the Scanner changes •σ into σ•
        new_item = Item.new(item.non_terminal,
                            item.left_pattern + [token],
                            item.right_pattern[1...item.right_pattern.size],
                            item.position)

        list[destination_position] ||= UniqueArray.new
        list[destination_position] << new_item
      end
    end
  
    # this runs the predictor
    # This implements the following rule from Practical Earley Parsing:
    # PREDICTOR. If [A → ...•B..., j] is in S[i], add [B → •α, i] to S[i] for all productions/rules B→α.
    def predict(item, position)
      # NOTE: A non-terminal is predicted by an item if the token to the right of the DOT is a non-terminal.
      # if item is of the form [A -> ...•B..., position] (where B is a non-terminal)...
      predicted_token = item.right_pattern.first
      if predicted_token.is_a?(Symbol)
        # ... then we add [B -> •α..., position] to list[position] for every production alternative B -> α
        list[position] += construct_initial_item_set(predicted_token, 
                                                     grammar.alternatives(predicted_token), 
                                                     position)
      end
    end

    # this runs the completer
    # This implements the following rule from Practical Earley Parsing:
    # COMPLETER. If [A → ...•, j] is in S[i], add [B → ...A•..., k] to S[i] for all items [B → ...•A..., k] in S[j].
    def complete(item, position)
      # If [A → ...•, j] is in S[i] ...
      if item.right_pattern.empty?
        # ... add [B → ...A•..., k] to S[i] for all items [B → ...•A..., k] in S[j].
        list[item.position].each do |reducing_item|
          scan(item.non_terminal, reducing_item, position)
        end
      end
    end
  end

  class PracticalEarleyEpsilonParser < PracticalEarleyParser
    # this runs the predictor
    # This implements the following rule from Practical Earley Parsing:
    # PREDICTOR. If [A → ...•B..., j] is in S[i], add [B → •α, i] to S[i] for all productions/rules B→α.
    #            If B is nullable, also add [A → ...B•..., j] to S[i].
    def predict(item, position)
      # NOTE: A non-terminal is predicted by an item if the token to the right of the DOT is a non-terminal.
      # if item is of the form [A -> ...•B..., position] (where B is a non-terminal)...
      predicted_token = item.right_pattern.first
      if predicted_token.is_a?(Symbol)
        # ... then we add [B -> •α..., position] to list[position] for every production alternative B -> α
        list[position] += construct_initial_item_set(predicted_token, 
                                                     grammar.alternatives(predicted_token), 
                                                     position)
        # If B is nullable, also add [A → ...B•..., j] to list[position]
        if grammar.nullable_non_terminals.include?(predicted_token)
          list[position] << Item.new(item.non_terminal,
                                     item.left_pattern + [item.right_pattern.first],
                                     item.right_pattern[1...item.right_pattern.size],
                                     item.position)
        end
      end
    end
  end
end