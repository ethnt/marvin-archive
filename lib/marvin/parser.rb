module Marvin

  # The Parser will verify the syntax of the found Tokens.
  class Parser
    attr_accessor :tokens, :cst, :ast, :symbol_table, :config

    # Creates a new Parser with a given Lexer and configuration.
    #
    # @param [Array<Marvin::Token>] tokens A bunch of tokens.
    # @param [Marvin::CST] cst A CST.
    # @param [Marvin::AST] ast An AST.
    # @param [Marvin::Configuration] config Configuration instance.
    # @return [Marvin::Parser] An un-run parser.
    def initialize(tokens, config = Marvin::Configuration.new)
      @tokens       = tokens
      @cst          = Marvin::CST.new
      @ast          = Marvin::AST.new
      @symbol_table = Marvin::SymbolTable.new
      @config       = config
    end

    # Will parse the tokens given.
    #
    # @return [Boolean] Whether the source is valid or not.
    def parse!
      @counter = 0

      @config.logger.info('Parsing...')

      if @tokens.empty?
        return Marvin::Error::ParseError.new(Marvin::Token.new('', :empty), :block_start)
      end

      # Get on your flip-flops! Going to parse until we're at the end of the
      # tokens.
      if @counter == 0 .. @tokens.length
        parse_program!
      end

      if @config.logger.verbose
        @config.logger.info("\n")
        @config.logger.info("Printing CST...\n")
        @config.logger.info(@cst.print_tree)

        @config.logger.info("\n")
        @config.logger.info("Printing AST...\n")
        @config.logger.info(@ast.print_tree)

        @config.logger.info("\n")
        @config.logger.info("Printing symbol table...\n")
        @config.logger.info(@symbol_table.print_tree)
      end

      @symbol_table.root.each do |node|
        if node.is_a?(Marvin::Variable)
          if node.content[:value].nil?
            @config.logger.warning("Declared but unused identifier #{node.name} on line #{node.content[:tokens].first.attributes[:line]}, character #{node.content[:tokens].first.attributes[:char]}.")
          end
        end
      end

      @config.logger.info("Parse completed successfully.\n\n")

      true
    end

    private

    # Checks whether or not the current token matches the expected kind.
    #
    # @param [Symbol] kind The expected kind.
    # @param [Marvin::Node] cst_node The current parent node for the CST.
    # @param [Marvin::Node] ast_node The current parent node for the AST.
    # @param [Boolean] fail_out Whether or not to return out if we don't find a
    #                           match.
    # @param [Boolean] advance Whether or not to advance the pointer if a match
    #                          is found.
    # @return [Boolean] Whether or not the kind matches.
    def match?(kind, cst_node: nil, ast_node: nil, table_node: nil, variable: nil, fail_out: true, advance: true)
      # We have a match.
      if current_token.kind == kind
        if advance
          cst_node << Marvin::Node.new(current_token) if cst_node
          ast_node << Marvin::Node.new(current_token) if ast_node
          # table_node << Marvin::Node.new(current_token) if table_node

          if variable
            variable.rename(current_token.lexeme) if [:char].include?(current_token.kind)
            variable.content[:type] = current_token.lexeme if current_token.kind == :type

            variable.content[:tokens] = [] unless variable.content[:tokens]
            variable.content[:tokens] << current_token

            if [:digit, :string, :boolval].include?(current_token.kind)
              variable.content[:value] = current_token.lexeme
            end
          end

          @counter += 1
        end

        true
      else
        return Marvin::Error::ParseError.new(current_token, kind) if fail_out

        false
      end
    end

    # Match against one of the given kinds.
    #
    # @param [Array<Symbol>] kinds The expected kinds to match against.
    #
    # @return [Boolean] Whether one of the kinds match.
    def match_any?(kinds, fail_out: false, advance: false)
      kinds.each do |kind|
        if match?(kind, fail_out: fail_out, advance: advance)
          return true
        end
      end

      false
    end

    # Returns the token at the counter.
    #
    # @return [Marvin::Token] The token at the counter.
    def current_token
      @tokens[@counter]
    end

    def next_token
      @tokens[@counter + 1]
    end

    # Parses a program.
    #
    #   Program ::= Block $
    #
    # @return [Boolean] Whether this parsing succeeds.
    def parse_program!
      @config.logger.info('  Parsing program...')

      cst_program_node = Marvin::Node.new(Marvin::Production.new('Program'))
      ast_program_node = Marvin::Node.new(Marvin::Production.new('Program'))
      table_program_node = Marvin::Node.new(Marvin::Production.new('Program'))

      @cst.root = cst_program_node
      @ast.root = ast_program_node
      @symbol_table.root = table_program_node

      parse_block!(cst_program_node, ast_program_node, table_program_node)
      match?(:program_end, cst_node: cst_program_node, ast_node: ast_program_node)

      # If there are more tokens, that means there is more than one program in
      # this file.
      # if current_token
      #   parse_program!
      # end
    end

    # Parses a block.
    #
    #   Block ::= { StatementList }
    #
    # @param [Marvin::Node] cst_node The current parent node for the CST.
    # @param [Marvin::Node] ast_node The current parent node for the AST.
    # @return [Boolean] Whether this parsing succeeds.
    def parse_block!(cst_node, ast_node, table_node)
      @config.logger.info('  Parsing block...')

      cst_block_node = Marvin::Node.new(Marvin::Production.new('Block'))
      ast_block_node = Marvin::Node.new(Marvin::Production.new('Block'))
      table_block_node = Marvin::Node.new(Marvin::Scope.new('Block'))

      cst_node << cst_block_node
      ast_node << ast_block_node
      table_node << table_block_node

      match?(:block_begin, cst_node: cst_block_node)
      parse_statement_list!(cst_block_node, ast_block_node, table_block_node)
      match?(:block_end, cst_node: cst_block_node)
    end

    # Parses a statement list.
    #
    #   StatementList ::= Statement StatementList
    #                 ::= ε
    #
    # @param [Marvin::Node] cst_node The current parent node for the CST.
    # @param [Marvin::Node] ast_node The current parent node for the AST.
    # @return [Boolean] Whether this parsing succeeds.
    def parse_statement_list!(cst_node, ast_node, table_node)
      @config.logger.info('  Parsing statement list...')

      kinds = [:print, :char, :type, :while, :if_statement, :block_begin]

      if match_any?(kinds)
        cst_statement_list_node = Marvin::Node.new(Marvin::Production.new('StatementList'))

        cst_node << cst_statement_list_node

        parse_statement!(cst_statement_list_node, ast_node, table_node)
        parse_statement_list!(cst_statement_list_node, ast_node, table_node)
      elsif match?(:block_end, fail_out: false, advance: false)
        true
      else
        return Marvin::Error::ParseError.new(current_token, kinds)
      end
    end

    # Parses a statement.
    #
    #   Statement ::== PrintStatement
    #             ::== AssignmentStatement
    #             ::== VarDecl
    #             ::== WhileStatement
    #             ::== IfStatement
    #             ::== Block
    #
    # @param [Marvin::Node] cst_node The current parent node for the CST.
    # @param [Marvin::Node] ast_node The current parent node for the AST.
    # @return [Boolean] Whether this parsing succeeds.
    def parse_statement!(cst_node, ast_node, table_node)
      @config.logger.info('  Parsing statement...')

      if match?(:print, fail_out: false, advance: false)
        return parse_print_statement!(cst_node, ast_node, table_node)
      end

      if match?(:char, fail_out: false, advance: false)
        return parse_assignment_statement!(cst_node, ast_node, table_node)
      end

      if match?(:type, fail_out: false, advance: false)
        return parse_var_decl!(cst_node, ast_node, table_node)
      end

      if match?(:while, fail_out: false, advance: false)
        return parse_while_statement!(cst_node, ast_node, table_node)
      end

      if match?(:if_statement, fail_out: false, advance: false)
        return parse_if_statement!(cst_node, ast_node, table_node)
      end

      if match?(:block_begin, fail_out: false, advance: false)
        return parse_block!(cst_node, ast_node, table_node)
      end

      return Marvin::Error::ParseError.new(token, [:print, :char, :type, :while, :if_statement, :block_begin])
    end

    # Parses a print statement.
    #
    #   PrintStatement ::== print ( Expr )
    #
    # @param [Marvin::Node] cst_node The current parent node for the CST.
    # @param [Marvin::Node] ast_node The current parent node for the AST.
    # @return [Boolean] Whether this parsing succeeds.
    def parse_print_statement!(cst_node, ast_node, table_node)
      @config.logger.info('  Parsing print statement...')

      cst_print_node = Marvin::Node.new(Marvin::Production.new('Print'))
      ast_print_node = Marvin::Node.new(Marvin::Production.new('Print'))

      cst_node << cst_print_node
      ast_node << ast_print_node

      match?(:print, cst_node: cst_print_node, fail_out: false)
      match?(:open_parenthesis, cst_node: cst_print_node, fail_out: false)
      parse_expr!(cst_print_node, ast_print_node, table_node)
      match?(:close_parenthesis, cst_node: cst_print_node, fail_out: false)
    end

    # Parses an assignment statement.
    #
    #   AssignmentStatement ::== Id = Expr
    #
    # @param [Marvin::Node] cst_node The current parent node for the CST.
    # @param [Marvin::Node] ast_node The current parent node for the AST.
    # @return [Boolean] Whether this parsing succeeds.
    def parse_assignment_statement!(cst_node, ast_node, table_node)
      @config.logger.info('  Parsing assignment statement...')

      cst_assignment_node = Marvin::Node.new(Marvin::Production.new('Assignment'))
      ast_assignment_node = Marvin::Node.new(Marvin::Production.new('Assignment'))

      cst_node << cst_assignment_node
      ast_node << ast_assignment_node

      variable = find_variable!(current_token.lexeme, table_node)

      if variable == nil
        @config.logger.warning("Uninitialized identifier #{current_token.lexeme} on line #{current_token.attributes[:line]}, character #{current_token.attributes[:char]}.")
      end

      parse_id!(cst_assignment_node, ast_assignment_node, table_node)
      match?(:assignment, cst_node: cst_assignment_node)
      parse_expr!(cst_assignment_node, ast_assignment_node, table_node, variable)
    end

    # Parses a variable declaration.
    #
    #   VarDecl ::== type Id
    #
    # @param [Marvin::Node] cst_node The current parent node for the CST.
    # @param [Marvin::Node] ast_node The current parent node for the AST.
    # @return [Boolean] Whether this parsing succeeds.
    def parse_var_decl!(cst_node, ast_node, table_node)
      @config.logger.info('  Parsing variable declaration...')

      cst_var_decl_node = Marvin::Node.new(Marvin::Production.new('VariableDeclaration'))
      ast_var_decl_node = Marvin::Node.new(Marvin::Production.new('VariableDeclaration'))

      cst_node << cst_var_decl_node
      ast_node << ast_var_decl_node

      variable = Marvin::Variable.new('', '')
      table_node.children.each do |child|
        if child.content[:value] == next_token.lexeme
          variable = child
        end
      end

      table_node << variable unless variable.parent == table_node

      match?(:type, cst_node: cst_var_decl_node, ast_node: ast_var_decl_node, table_node: table_node, variable: variable)
      parse_id!(cst_var_decl_node, ast_var_decl_node, table_node, variable)
    end

    # Parses a while statement.
    #
    #   WhileStatement ::== while BooleanExpr Block
    #
    # @param [Marvin::Node] cst_node The current parent node for the CST.
    # @param [Marvin::Node] ast_node The current parent node for the AST.
    # @return [Boolean] Whether this parsing succeeds.
    def parse_while_statement!(cst_node, ast_node, table_node)
      @config.logger.info('  Parsing while statement...')

      cst_while_node = Marvin::Node.new(Marvin::Production.new('WhileStatement'))
      ast_while_node = Marvin::Node.new(Marvin::Production.new('WhileStatement'))

      cst_node << cst_while_node
      ast_node << ast_while_node

      match?(:while, cst_node: cst_while_node)
      parse_boolean_expr!(cst_while_node, ast_while_node, table_node)
      parse_block!(cst_while_node, ast_while_node, table_node)
    end

    # Parses an if statement.
    #
    #   IfStatement ::== if BooleanExpr Block
    #
    # @param [Marvin::Node] cst_node The current parent node for the CST.
    # @param [Marvin::Node] ast_node The current parent node for the AST.
    # @return [Boolean] Whether this parsing succeeds.
    def parse_if_statement!(cst_node, ast_node, table_node)
      @config.logger.info('  Parsing if statement...')

      cst_if_node = Marvin::Node.new(Marvin::Production.new('IfStatement'))
      ast_if_node = Marvin::Node.new(Marvin::Production.new('IfStatement'))

      cst_node << cst_if_node
      ast_node << ast_if_node

      match?(:if_statement, cst_node: cst_if_node)
      parse_boolean_expr!(cst_if_node, ast_if_node, table_node)
      parse_block!(cst_if_node, ast_if_node, table_node)
    end

    # Parses an expression.
    #
    #   Expr ::== IntExpr
    #        ::== StringExpr
    #        ::== BooleanExpr
    #        ::== Id
    #
    # @param [Marvin::Node] cst_node The current parent node for the CST.
    # @param [Marvin::Node] ast_node The current parent node for the AST.
    # @return [Boolean] Whether this parsing succeeds.
    def parse_expr!(cst_node, ast_node, table_node, variable = nil)
      @config.logger.info('  Parsing expression...')

      if match?(:digit, fail_out: false, advance: false)
        parse_int_expr!(cst_node, ast_node, table_node, variable)
      elsif match?(:string, fail_out: false, advance: false)
        parse_string_expr!(cst_node, ast_node, table_node, variable)
      elsif match?(:boolval, fail_out: false, advance: false) || match?(:open_parenthesis, fail_out: false, advance: false)
        parse_boolean_expr!(cst_node, ast_node, table_node, variable)
      elsif match?(:char, fail_out: false, advance: false)
        parse_id!(cst_node, ast_node, table_node, variable)
      else

      end
    end

    # Parses an integer expression.
    #
    #   IntExpr ::== digit intop Expr
    #           ::== digit
    #
    # @param [Marvin::Node] cst_node The current parent node for the CST.
    # @param [Marvin::Node] ast_node The current parent node for the AST.
    # @return [Boolean] Whether this parsing succeeds.
    def parse_int_expr!(cst_node, ast_node, table_node, variable = nil)
      @config.logger.info('  Parsing integer expression...')

      match?(:digit, cst_node: cst_node, ast_node: ast_node, table_node: table_node, variable: variable)

      return parse_expr!(cst_node, ast_node, table_node) if match?(:intop, fail_out: false)
    end

    # Parses a string expression.
    #
    #   StringExpr ::= " CharList "
    #
    # @param [Marvin::Node] cst_node The current parent node for the CST.
    # @param [Marvin::Node] ast_node The current parent node for the AST.
    # @return [Boolean] Whether this parsing succeeds.
    def parse_string_expr!(cst_node, ast_node, table_node, variable = nil)
      @config.logger.info('  Parsing string expression...')

      match?(:string, cst_node: cst_node, ast_node: ast_node, table_node: table_node, variable: variable)
    end

    # Parses a boolean expression.
    #
    #   BooleanExpr ::= ( Expr boolop Expr )
    #               ::= boolval
    #
    # @param [Marvin::Node] cst_node The current parent node for the CST.
    # @param [Marvin::Node] ast_node The current parent node for the AST.
    # @return [Boolean] Whether this parsing succeeds.
    def parse_boolean_expr!(cst_node, ast_node, table_node, variable = nil)
      @config.logger.info('  Parsing boolean expression...')

      cst_boolean_expr_node = Marvin::Node.new(Marvin::Production.new('BooleanExpr'))
      ast_boolean_expr_node = Marvin::Node.new(Marvin::Production.new('BooleanExpr'))

      cst_node << cst_boolean_expr_node
      ast_node << ast_boolean_expr_node

      if match?(:open_parenthesis, fail_out: false, advance: false)
        match?(:open_parenthesis, cst_node: cst_boolean_expr_node)
        parse_expr!(cst_boolean_expr_node, ast_boolean_expr_node, table_node, variable)
        match?(:boolop, cst_node: cst_boolean_expr_node, ast_node: ast_boolean_expr_node)
        parse_expr!(cst_boolean_expr_node, ast_boolean_expr_node, table_node, variable)
        match?(:close_parenthesis, cst_node: cst_boolean_expr_node)
      else
        match?(:boolval, cst_node: cst_boolean_expr_node, ast_node: ast_boolean_expr_node, variable: variable)
      end
    end

    # Parses an identifier.
    #
    #   Id ::== char
    #
    # @param [Marvin::Node] cst_node The current parent node for the CST.
    # @param [Marvin::Node] ast_node The current parent node for the AST.
    # @return [Boolean] Whether this parsing succeeds.
    def parse_id!(cst_node, ast_node, table_node, variable = nil)
      @config.logger.info('  Parsing identifier...')

      match?(:char, cst_node: cst_node, ast_node: ast_node, table_node: table_node, variable: variable)
    end

    def find_variable!(name, current_block)
      variable = nil

      current_block.children.each do |child|
        if child.name == name
          variable = child
        end
      end

      if variable == nil && current_block.parent
        find_variable!(name, current_block.parent)
      end

      variable
    end
  end
end
