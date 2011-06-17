
module Linguist
  # This represents an Earley Item.
  # From the Parsing Techniques book:
  #   An Item is a production with a gap in its right-hand side.
  #   The first "half" (the left-hand portion) of the production's right-hand side is the portion of the pattern
  #   that has already been recognized.
  #   The last "half" (the right-hand portion) .
  #   An Earley Item is an Item with an indication of the position of the symbol at which the 
  #   recognition of the recognized part started.
  #   The Item E-->E•QF@3 would be represented using this structure as:
  #   Item.new(:E, [:E], [:Q, :F], 3)
  Item = Struct.new(:non_terminal, :left_pattern, :right_pattern, :position)

  class EarleyParser
    attr_reader :grammar
    attr_reader :completed, :active, :predicted
  
    def initialize(bnf_grammar)
      @grammar = bnf_grammar
    
      # these collections hold a set of items per token in the input stream
      # they are covered in detail on page 207 of Parsing Techniques (2nd ed.)
      @completed = []
      @active = []
      @predicted = []
    end
  
    def reset
      @completed = []
      @active = []
      @predicted = []
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
  
    def itemset(position)
      active[position] + predicted[position]
    end
  
    private
  
    # alternatives is an array of pattern sequences, where each pattern sequence is an array of terminals and non-terminals.
    def construct_initial_item_set(non_terminal, alternatives, position)
      Set.new(alternatives.map {|pattern| Item.new(non_terminal, [], pattern, position) })
    end
  
    def recognize(token_stream)
      build_initial_itemset

      token_stream.each_with_index do |token, position|
        scan(token, position, position + 1)
        complete(position)
        predict(position)
      end
    
      # If the completed set after the last symbol in the input contains an item 
      # S -> ...•@1, that is, an item spanning the entire input and reducing to the start symbol,
      # we have found a parsing.
      (completed[token_stream.count] || []).any? do |item|
        item.non_terminal == grammar.start &&
        item.right_pattern.empty? &&
        item.position == 0
      end
    end
  
    def build_initial_itemset
      active[0] = construct_initial_item_set(grammar.start, grammar.alternatives(grammar.start), 0)
      predict(-1)
    end
  
    # this runs the scanner
    def scan(token, source_position, destination_position)
      # these items represent items that contain •σ somewhere in the item's pattern (σ is the token; σ === token)
      items_to_be_copied = itemset(source_position).select do |item|
        item.right_pattern.first == token || item.right_pattern.first == Pattern::DOT
      end
    
      # In the copied items, the part before the dot was already recognized and now σ is recognized;
      # consequently, the Scanner changes •σ into σ•
      # σ === token
      modified_items = items_to_be_copied.map do |item|
        Item.new(item.non_terminal,
                 item.left_pattern + [token],
                 item.right_pattern[1...item.right_pattern.size],
                 item.position) 
      end
    
      # separate out the completed items and the active items from modified_items
      reduce_items, active_items = modified_items.partition {|item| item.right_pattern.empty? }
    
      completed[destination_position] ||= Set.new
      completed[destination_position] += reduce_items
    
      active[destination_position] ||= Set.new
      active[destination_position] += active_items
    end
  
    # this runs the completer
    def complete(position)
      # this is the closure of the scan/complete action
      begin
        reduce_items = completed[position + 1]
      
        # for each item of the form R -> ...•@m the Completer goes to itemset[m], and calls scan(R, m, position + 1)
        reduce_items.each do |item|
          scan(item.non_terminal, item.position, position + 1)
        end
      
        new_reduce_items = completed[position + 1]
      end until new_reduce_items == reduce_items
    end
  
    # this runs the predictor
    def predict(position)
      predicted[position + 1] ||= Set.new

      predict_items(active[position + 1], position)

      # this is the closure of the predict action
      begin
        original_predicted_items = predicted[position + 1]
      
        predict_items(original_predicted_items, position)
      
        new_predicted_items = predicted[position + 1]
      end until new_predicted_items == original_predicted_items
    end
  
    def predict_items(item_collection, position)
      # build a list of non-terminals that are predicted by the items in item_collection. A non-terminal is predicted
      # by an item if the token to the right of the DOT is a non-terminal.
      predicted_non_terminals = item_collection.map do |item|
        predicted_token = item.right_pattern.first
        predicted_token.is_a?(Symbol) ? predicted_token : nil
      end.compact.uniq
      # "For each such non-terminal N and for each rule for that non-terminal N -> P..., the Predictor adds an
      #   item N -> •P...@p+1 to the set predicted[p+1]."
      predicted_non_terminals.each do |predicted_token|
        predicted[position + 1] += construct_initial_item_set(predicted_token, 
                                                              grammar.alternatives(predicted_token), 
                                                              position + 1)
      end
    end
  
    def parse_trees
    end
  end

  #########################################################
  ########## THE FOLLOWING IS A WORK IN PROGRESS ##########
  #########################################################

  # This Earley parser supports epsilon productions (productions in which an epsilon 
  # appears in one of the production's alternatives).
  class EarleyEpsilonParser < EarleyParser
    # this runs the scanner
    def scan(token, source_position, destination_position)
      # these items represent items that contain •σ somewhere in the item's pattern (σ is the token; σ === token)
      items_to_be_copied = itemset(source_position).select do |item|
        item.right_pattern.first == token # || item.right_pattern.empty?
      end
    
      # In the copied items, the part before the dot was already recognized and now σ is recognized;
      # consequently, the Scanner changes •σ into σ•
      # σ === token
      modified_items = items_to_be_copied.map do |item|
        # if item.right_pattern.empty?
        #   Item.new(item.non_terminal,
        #            item.left_pattern,
        #            item.right_pattern,
        #            item.position)
        # else
          Item.new(item.non_terminal,
                   item.left_pattern + [item.right_pattern.first],
                   item.right_pattern[1...item.right_pattern.size],
                   item.position)
        # end
      end
    
      # separate out the completed items and the active items from modified_items
      reduce_items, active_items = modified_items.partition {|item| item.right_pattern.empty? }
    
      completed[destination_position] ||= Set.new
      completed[destination_position] += reduce_items
    
      active[destination_position] ||= Set.new
      active[destination_position] += active_items
    end
  
    # This implements Aycock and Horspool's solution of modifying the predictor to handle epsilon productions.
    # "The Predictor is modified as follows. 
    # When presented with an item R -> ···•N··· it predicts all items of the 
    #   form N -> •··· as usual, but if N is nullable it also predicts the item R -> ···N•···."
    def predict_items(item_collection, position)
      # predicted_non_terminals_and_items is a hash of the form:
      # {predicted_non_terminal => [item1_that_predicts_the_non_terminal, item2_that_predicts_the_non_terminal, ...], ...}
      predicted_non_terminals_and_items = item_collection.reduce({}) do |memo,item|
        predicted_token = item.right_pattern.first
        # if the predicted token is a non-terminal or epsilon (i.e. nothing/nil)
        if predicted_token.is_a?(Symbol)  # || predicted_token.nil?
          memo[predicted_token] ||= []
          memo[predicted_token] << item
        end
        memo
      end
    
      # build a list of non-terminals that are predicted by the items in item_collection. A non-terminal is predicted
      # by an item if the token to the right of the DOT is a non-terminal.
      predicted_non_terminals = predicted_non_terminals_and_items.keys
    
      # "For each such non-terminal N and for each rule for that non-terminal N -> P..., the Predictor adds an
      #   item N -> •P...@p+1 to the set predicted[p+1]."
      predicted_non_terminals.each do |predicted_token|
        # if predicted_token    # predicted_token is non-nil
          predicted[position + 1] += construct_initial_item_set(predicted_token, 
                                                                grammar.alternatives(predicted_token), 
                                                                position + 1)
          # if N is nullable, we also predict the item R -> ···N•···."
          if grammar.nullable_non_terminals.include?(predicted_token)
            predicted_items = predicted_non_terminals_and_items[predicted_token].map do |predicting_item|
              Item.new(predicting_item.non_terminal,
                       predicting_item.left_pattern + [predicting_item.right_pattern.first],
                       predicting_item.right_pattern[1...predicting_item.right_pattern.size],
                       predicting_item.position)
            end
          
            # separate out the completed items and the active items from modified_items
            reduce_items, predicted_items = predicted_items.partition {|item| item.right_pattern.empty? }

            completed[position + 1] ||= Set.new
            completed[position + 1] += reduce_items
          
            predicted[position + 1] += predicted_items
          end
        # else    # predicted_token is nil, meaning, epsilon
        #   predicted_items = predicted_non_terminals_and_items[predicted_token].map do |predicting_item|
        #     Item.new(predicting_item.non_terminal,
        #              predicting_item.left_pattern,
        #              [],
        #              predicting_item.position)
        #   end
        #   predicted[position + 1] += predicted_items
        # end
      end
    end
  end
end